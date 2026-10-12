# 独立合并模型诊断：不读取旧版本模型，不拟合周期模型。
source("scripts/pooled_only_v3/config.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1 || !args %in% c("--self-test", "--run")) {
  stop("diagnose.R 只接受 --self-test 或 --run")
}

# 存在所有有符号间隔均非负、至少一个为正的方向即完全或准完全分离。
# 将系数拆成正负部分，并施加L1界，使线性规划有界。
separation <- function(X, y) {
  stopifnot(is.matrix(X), nrow(X) == length(y), nrow(X) > 0,
            all(is.finite(X)), all(y %in% c(0, 1)))
  scales <- apply(abs(X), 2, max)
  X <- sweep(X, 2, pmax(scales, 1), "/")
  A <- X * (2 * y - 1)
  p <- ncol(X)
  constraints <- rbind(cbind(A, -A), rep(1, 2 * p))
  fit <- lpSolve::lp(
    "max", c(colSums(A), -colSums(A)), constraints,
    c(rep(">=", nrow(A)), "<="), c(rep(0, nrow(A)), 1),
    transpose.constraints = TRUE
  )
  list(status = fit$status, objective = fit$objval,
       separated = if (fit$status == 0) fit$objval > 1e-7 else NA)
}

self_test <- function() {
  stopifnot(separation(cbind(1, c(0, 1)), c(0, 1))$separated,
            separation(cbind(1, c(0, 0, 1)), c(0, 1, 1))$separated,
            !separation(cbind(1, c(0, 0, 1, 1)), c(0, 1, 0, 1))$separated)
  candidate_forms <- c(forms, list(
    age_subgroup = forms$M3,
    sex_subgroup = update(forms$M3, . ~ . - sex),
    age_interaction = update(forms$M3, . ~ . + agegroup + ra:agegroup),
    sex_interaction = update(forms$M3, . ~ . + ra:sex)
  ))
  invisible(lapply(candidate_forms, assert_formula))
  for (term in c("year", "cycle", "era", "period", "factor(year)", "ra:cycle")) {
    rejected <- try(assert_formula(as.formula(paste("asthma ~ ra +", term))), silent = TRUE)
    stopifnot(inherits(rejected, "try-error"))
  }
  message("诊断自检通过：完全分离、准完全分离、无分离对照；周期变量拦截。")
}
self_test()
if (args == "--self-test") quit(status = 0)

write_result <- function(x, name) {
  write.csv(x, file.path(out, paste0(name, ".csv")), row.names = FALSE, na = "")
}
diagnose <- function() {
  stopifnot(file.exists(file.path(out, "analysis_gate.json")),
            file.exists(file.path(out, "input_binding.json")),
            file.exists(file.path(diagnostic_dir, "models.rds")))
  binding <- fromJSON(file.path(out, "input_binding.json"))
  hashes <- unlist(binding$input_md5)
  stopifnot(all(file.exists(names(hashes))),
            identical(unname(tools::md5sum(names(hashes))), unname(hashes)))
  models <- readRDS(file.path(diagnostic_dir, "models.rds"))
  diag <- read.csv(file.path(out, "model_diagnostics.csv"))
  expected <- c("M0", "M1", "M2", "M3", "agegroup_20_39", "agegroup_40_59",
                "agegroup_60_79", "sex_Male", "sex_Female",
                "interaction_agegroup", "interaction_sex")
  stopifnot(!anyDuplicated(diag$model), setequal(diag$model, expected))
  formula_audit <- lapply(names(models), function(label) {
    form <- formula(models[[label]])
    assert_formula(form)
    data.frame(model = label, formula = paste(deparse(form), collapse = " "),
               period_term_present = FALSE)
  })
  write_result(bind_rows(formula_audit), "model_formula_audit")

  checks <- lapply(diag$model, function(label) {
    path <- file.path(diagnostic_dir, paste0("separation_", label, ".rds"))
    if (!file.exists(path)) {
      return(data.frame(model = label, solver_status = NA_integer_,
                        objective = NA_real_, separated = NA))
    }
    input <- readRDS(path)
    r <- separation(input$X, input$y)
    data.frame(model = label, solver_status = r$status, objective = r$objective,
               separated = r$separated)
  })
  checks <- bind_rows(checks)
  write_result(checks, "separation_checks")
  diag <- left_join(diag, checks, by = "model", relationship = "one-to-one")
  valid <- diag$status != "not_estimable" & !is.na(diag$separated) &
    !diag$separated & !is.na(diag$solver_status) & diag$solver_status == 0 &
    diag$model %in% names(models)
  diag$status <- ifelse(valid, "estimable", "not_estimable")
  write_result(diag, "model_diagnostics")
  for (name in c("regression", "subgroups", "all_model_coefficients")) {
    tab <- read.csv(file.path(out, paste0(name, ".csv")))
    tab$status <- diag$status[match(tab$model, diag$model)]
    stopifnot(!anyNA(tab$status))
    tab[tab$status != "estimable", c("OR", "lower", "upper", "p")] <- NA
    write_result(tab, name)
  }
  interactions <- read.csv(file.path(out, "interaction_tests.csv"))
  stopifnot(setequal(interactions$variable, c("agegroup", "sex")))
  interactions$status <- diag$status[match(paste0("interaction_", interactions$variable), diag$model)]
  stopifnot(!anyNA(interactions$status))
  interactions$status[!is.finite(interactions$F) | !is.finite(interactions$p)] <- "not_estimable"
  interactions[interactions$status != "estimable", c("F", "p")] <- NA
  write_result(interactions, "interaction_tests")

  # 仅保留原完全调整模型的数值诊断，不新增研究问题。
  if (diag$status[diag$model == "M3"] == "estimable") {
    m <- models$M3
    z <- m$survey.design$variables
    z$residual <- z$asthma - fitted(m)
    z$predicted <- fitted(m)
    residuals <- lapply(c("age", "bmi", "pir"), function(variable) {
      cuts <- unique(as.numeric(quantile(z[[variable]], probs = seq(0, 1, length.out = 11))))
      z$bin <- cut(z[[variable]], cuts, include.lowest = TRUE)
      z %>% group_by(bin) %>% summarise(
        n = n(), mean_x = weighted.mean(.data[[variable]], analysis_weight),
        observed = weighted.mean(asthma, analysis_weight),
        predicted = weighted.mean(predicted, analysis_weight),
        residual = weighted.mean(residual, analysis_weight), .groups = "drop"
      ) %>% mutate(variable = variable)
    })
    write_result(bind_rows(residuals), "binned_model_residuals")
  }
  success <- all(diag$status == "estimable") && setequal(names(models), expected) &&
    all(interactions$status == "estimable")
  write_json(list(verdict = if (success) "pass" else "revise", model_count = nrow(diag),
                  period_term_present = FALSE, separation_method = "bounded linear program",
                  threshold = 1e-7), file.path(out, "model_gate.json"),
             auto_unbox = TRUE, pretty = TRUE)
  writeLines(capture.output(sessionInfo()), file.path(out, "environment_diagnostics.txt"))
  # 运行/数值诊断通过不等于完成独立结果复核或报告审阅。
  write_json(list(verdict = if (success) "pass" else "revise", result_ready = success,
                  readiness_scope = "pipeline and numerical diagnostics only",
                  scientific_review = "needs evidence"), file.path(out, "run_gate.json"),
             auto_unbox = TRUE, pretty = TRUE)
  if (!success) stop("存在不可估计或未通过诊断的模型；需检查 model_diagnostics.csv")
  message("统一分析及数值诊断完成；报告更新前仍需独立复核。")
}
tryCatch(diagnose(), error = function(error) {
  if (dir.exists(out)) {
    write_json(list(verdict = "revise", result_ready = FALSE,
                    error = conditionMessage(error)), file.path(out, "run_gate.json"),
               auto_unbox = TRUE, pretty = TRUE)
  }
  stop(conditionMessage(error), call. = FALSE)
})
