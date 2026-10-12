# 隔离的合成数据端到端检查：不读取或拟合NHANES参与者数据。
source("scripts/pooled_only_v3/config.R")
validate_code <- function() {
  sandbox <- tempfile("pooled_v03_synthetic_")
  dir.create(sandbox)
  on.exit(unlink(sandbox, recursive = TRUE), add = TRUE)
  set.seed(20261012)
  n <- 2400
  z <- data.frame(
    SEQN = seq_len(n), year = rep(c(2003L, 2021L), each = n / 2),
    SDMVSTRA = rep(seq_len(30), each = 80),
    SDMVPSU = rep(rep(1:2, each = 40), 30),
    analysis_weight = runif(n, 1, 4), design_valid = TRUE, eligible = TRUE,
    age = sample(20:79, n, replace = TRUE),
    sex = factor(sample(c("Male", "Female"), n, TRUE), levels = c("Male", "Female")),
    race = factor(sample(c("A", "B", "C"), n, TRUE)),
    education = factor(sample(c("A", "B", "C"), n, TRUE)),
    pir = runif(n, .1, 5), bmi = runif(n, 18, 40),
    smoking = factor(sample(c("Never", "Former", "Current"), n, TRUE)),
    ra = rbinom(n, 1, .25)
  )
  z$agegroup <- cut(z$age, breaks = c(19, 39, 59, 79),
                    labels = c("20-39", "40-59", "60-79"))
  z$pirgroup <- cut(z$pir, breaks = c(0, 1, 3, 6))
  z$bmigroup <- cut(z$bmi, breaks = c(0, 25, 30, 50))
  z$asthma <- rbinom(n, 1, plogis(-2 + .45 * z$ra + .008 * (z$age - 50)))
  fixture <- file.path(sandbox, "synthetic_frame.rds")
  saveRDS(z, fixture)
  env <- new.env(parent = globalenv())
  env$root <- sandbox
  env$out <- file.path(sandbox, "summary")
  env$diagnostic_dir <- file.path(sandbox, "models")
  env$commandArgs <- function(trailingOnly = FALSE) "--run"
  env$check_input <- function() list(frame = z, input_md5 = as.list(tools::md5sum(fixture)))
  # 仅跳过已在本测试载入的config，保留其余真实分析及诊断代码。
  run_body <- function(file) {
    expressions <- parse(file)
    stopifnot(identical(expressions[[1]], quote(source("scripts/pooled_only_v3/config.R"))))
    for (expression in expressions[-1]) eval(expression, env)
  }
  invisible(capture.output(run_body("scripts/pooled_only_v3/analyze.R")))
  run_body("scripts/pooled_only_v3/diagnose.R")
  gate <- fromJSON(file.path(env$out, "run_gate.json"))
  stopifnot(gate$verdict == "pass", gate$result_ready)
  tab <- read.csv(file.path(env$out, "regression.csv"))
  stopifnot(nrow(tab) == 4, all(tab$status == "estimable"), all(tab$n == n))
  subgroup <- read.csv(file.path(env$out, "subgroups.csv"))
  stopifnot(nrow(subgroup) == 5, all(subgroup$status == "estimable"))
  interaction <- read.csv(file.path(env$out, "interaction_tests.csv"))
  stopifnot(nrow(interaction) == 2, all(is.finite(interaction$p)))
  diag <- read.csv(file.path(env$out, "model_diagnostics.csv"))
  stopifnot(nrow(diag) == 11, all(diag$status == "estimable"))
  # 故意让一个交互模型诊断失败，必须屏蔽其检验并关闭结果就绪标记。
  diag$status[diag$model == "interaction_sex"] <- "not_estimable"
  diag <- diag[, setdiff(names(diag), c("solver_status", "objective", "separated"))]
  write.csv(diag, file.path(env$out, "model_diagnostics.csv"), row.names = FALSE)
  rejected <- try(run_body("scripts/pooled_only_v3/diagnose.R"), silent = TRUE)
  stopifnot(inherits(rejected, "try-error"))
  gate <- fromJSON(file.path(env$out, "run_gate.json"))
  interaction <- read.csv(file.path(env$out, "interaction_tests.csv"))
  stopifnot(gate$verdict == "revise", !gate$result_ready,
            is.na(interaction$p[interaction$variable == "sex"]))
  # 新版禁止覆盖已经存在的结果目录。
  rejected <- try(run_body("scripts/pooled_only_v3/analyze.R"), silent = TRUE)
  stopifnot(inherits(rejected, "try-error"), grepl("输出目录已存在", rejected))
  message("合成数据端到端检查通过：4主模型、5亚组、2交互；失败屏蔽及防覆盖通过。")
}
validate_code()
