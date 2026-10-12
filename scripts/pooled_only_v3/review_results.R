# 本轮运行后的只读数据复核：只保存汇总审核表，不修改模型及其结果。
source("scripts/pooled_only_v3/config.R")
audit_dir <- file.path(out, "review")
if (dir.exists(audit_dir)) stop("审核目录已存在；拒绝覆盖")
stopifnot(dir.create(audit_dir, recursive = TRUE))
write_table <- function(x, name) write.csv(x, file.path(audit_dir, paste0(name, ".csv")),
                                         row.names = FALSE, na = "")
checks <- list()
check <- function(name, value, tolerance = 0) {
  pass <- length(value) == 1 && is.finite(value) && abs(value) <= tolerance
  checks[[length(checks) + 1]] <<- data.frame(check = name, error = value,
                                           tolerance = tolerance, pass = pass)
  if (!pass) stop("复核失败：", name, "; error=", value)
}
review <- function() {
  gate <- fromJSON(file.path(out, "run_gate.json"))
  stopifnot(gate$verdict == "pass", gate$result_ready)
  binding <- fromJSON(file.path(out, "input_binding.json"))
  hashes <- unlist(binding$input_md5)
  check("input_hashes_unchanged", sum(unname(tools::md5sum(names(hashes))) != unname(hashes)))
  d <- readRDS(file.path(root, "derived", "analysis_frame.rds"))
  models <- readRDS(file.path(diagnostic_dir, "models.rds"))
  broad <- d[d$design_valid, ]
  z <- d[d$eligible, ]
  check("unique_participant", anyDuplicated(d$SEQN))

  # 用保留的问卷原始字段重新构造纳入条件；不是重新读取XPT。
  yes <- function(x) !is.na(x) & x
  expected_type <- ifelse(d$year < 2009, d$MCQ190,
                          ifelse(d$year == 2009, d$MCQ191, d$MCQ195))
  type_equal <- (is.na(expected_type) & is.na(d$arthritis_type)) |
    yes(expected_type == d$arthritis_type)
  check("arthritis_type_field_selection", sum(!type_equal))
  ra_alt <- yes(d$MCQ160A == 1 & expected_type == ifelse(d$year < 2011, 1, 2))
  control_alt <- yes(d$MCQ160A == 2)
  smoke_alt <- yes(d$SMQ020 == 2 | (d$SMQ020 == 1 & d$SMQ040 %in% 1:3))
  prerequisites <- list(
    age_20_79 = yes(d$RIDAGEYR >= 20 & d$RIDAGEYR <= 79),
    valid_MEC_design = yes(is.finite(d$analysis_weight) & d$analysis_weight > 0 &
                             !is.na(d$SDMVSTRA) & !is.na(d$SDMVPSU)),
    known_ever_asthma = d$MCQ010 %in% 1:2,
    RA_or_explicit_no_arthritis = ra_alt | control_alt,
    sex = d$RIAGENDR %in% 1:2,
    race = d$RIDRETH1 %in% 1:5,
    education = d$DMDEDUC2 %in% 1:5,
    pir = yes(is.finite(d$INDFMPIR) & d$INDFMPIR >= 0 & d$INDFMPIR <= 5),
    bmi = yes(is.finite(d$BMXBMI) & d$BMXBMI > 0),
    smoking = smoke_alt
  )
  keep <- rep(TRUE, nrow(d))
  flow <- list(data.frame(step = "All_DEMO", entered = nrow(d), excluded = 0, remaining = nrow(d)))
  for (name in names(prerequisites)) {
    entered <- sum(keep)
    keep <- keep & prerequisites[[name]]
    flow[[length(flow) + 1]] <- data.frame(step = name, entered = entered,
                                        excluded = entered - sum(keep), remaining = sum(keep))
  }
  check("independent_complete_case_flags", sum(keep != d$eligible))
  check("asthma_coding_in_cohort", sum(z$asthma != as.numeric(z$MCQ010 == 1)))
  check("RA_coding_in_cohort", sum(z$ra != as.numeric(ra_alt[d$eligible])))
  write_table(bind_rows(flow), "sample_flow")
  before_covariates <- Reduce(`&`, prerequisites[1:4])
  check("pre_covariate_flags", sum(before_covariates != d$pre_covariate))
  missing <- bind_rows(lapply(names(prerequisites)[5:10], function(name) {
    data.frame(variable = name, denominator = sum(before_covariates),
               missing = sum(before_covariates & !prerequisites[[name]]),
               percent = 100 * sum(before_covariates & !prerequisites[[name]]) / sum(before_covariates))
  }))
  write_table(missing, "missingness")
  write_table(z %>% count(ra, asthma, name = "n"), "disease_counts")

  prevalence <- read.csv(file.path(out, "asthma_prevalence.csv"))
  for (group in prevalence$group) {
    zz <- if (group == "All") z else z[z$ra == ifelse(group == "RA", 1, 0), ]
    row <- prevalence[prevalence$group == group, ]
    check(paste0("prevalence_", group), weighted.mean(zz$asthma, zz$analysis_weight) - row$estimate, 1e-12)
    check(paste0("n_", group), nrow(zz) - row$n)
    check(paste0("events_", group), sum(zz$asthma) - row$events)
  }
  p1 <- prevalence$estimate[prevalence$group == "RA"]
  p0 <- prevalence$estimate[prevalence$group == "No_arthritis"]
  check("unadjusted_weighted_odds_identity", (p1 / (1 - p1)) / (p0 / (1 - p0)) -
          exp(coef(models$M0)["ra"]), 1e-8)

  # 从各层/PSU得分和零贡献PSU独立重建Taylor三明治方差。
  # 不使用survey方差函数来构造结果；最后才与保存的协方差比较。
  psus <- unique(broad[, c("SDMVSTRA", "SDMVPSU")])
  psus$key <- paste(psus$SDMVSTRA, psus$SDMVPSU, sep = "_")
  tables <- bind_rows(read.csv(file.path(out, "regression.csv")),
                      read.csv(file.path(out, "subgroups.csv")))
  interactions <- read.csv(file.path(out, "interaction_tests.csv"))
  audit <- list()
  for (name in names(models)) {
    m <- models[[name]]
    form <- formula(m)
    assert_formula(form)
    zz <- m$survey.design$variables
    expected_ids <- if (grepl("^agegroup_", name)) {
      z$SEQN[z$agegroup == gsub("_", "-", sub("^agegroup_", "", name))]
    } else if (grepl("^sex_", name)) {
      z$SEQN[z$sex == sub("^sex_", "", name)]
    } else z$SEQN
    check(paste0(name, "_participant_domain"), sum(!zz$SEQN %in% expected_ids) +
            sum(!expected_ids %in% zz$SEQN))
    X <- model.matrix(form, zz)
    bread <- solve(crossprod(X, X * as.numeric(m$weights)))
    score <- X * (as.numeric(residuals(m, type = "working")) * as.numeric(m$weights))
    clustered <- rowsum(score, paste(zz$SDMVSTRA, zz$SDMVPSU, sep = "_"))
    U <- matrix(0, nrow(psus), ncol(X))
    U[match(rownames(clustered), psus$key), ] <- clustered
    meat <- matrix(0, ncol(X), ncol(X))
    for (stratum in unique(psus$SDMVSTRA)) {
      u <- U[psus$SDMVSTRA == stratum, , drop = FALSE]
      count <- nrow(u)
      stopifnot(count > 1)
      centered <- sweep(u, 2, colMeans(u), "-")
      meat <- meat + count / (count - 1) * crossprod(centered)
    }
    independent_vcov <- bread %*% meat %*% bread
    check(paste0(name, "_Taylor_covariance"), max(abs(independent_vcov - vcov(m))), 1e-9)
    df <- degf(m$survey.design)
    if (!grepl("^interaction_", name)) {
      row <- tables[tables$model == name, ]
      b <- coef(m)["ra"]
      se <- sqrt(independent_vcov["ra", "ra"])
      inferred <- c(OR = exp(b), lower = exp(b - qt(.975, df) * se),
                    upper = exp(b + qt(.975, df) * se),
                    p = 2 * pt(abs(b / se), df, lower.tail = FALSE))
      check(paste0(name, "_reported_inference"), max(abs(unlist(row[c("OR", "lower", "upper", "p")]) -
              unname(inferred))), 1e-9)
      check(paste0(name, "_reported_n"), row$n - nrow(zz))
    } else {
      variable <- sub("^interaction_", "", name)
      idx <- grep(paste0("^ra:", variable), names(coef(m)))
      b <- coef(m)[idx]
      q <- length(idx)
      stopifnot(q > 0)
      F <- as.numeric(t(b) %*% solve(independent_vcov[idx, idx, drop = FALSE], b) / q)
      p <- pf(F, q, df, lower.tail = FALSE)
      row <- interactions[interactions$variable == variable, ]
      check(paste0(name, "_joint_Wald_F"), F - row$F, 1e-9)
      check(paste0(name, "_joint_Wald_p"), p - row$p, 1e-9)
    }
    if (name %in% c("M0", "M1", "M2", "M3")) {
      reference_fit <- glm(form, data = zz, weights = analysis_weight / mean(analysis_weight),
                           family = quasibinomial(), control = glm.control(maxit = 100, epsilon = 1e-12))
      check(paste0(name, "_glm_coefficients"), max(abs(coef(reference_fit) - coef(m))), 1e-8)
    }
    audit[[length(audit) + 1]] <- data.frame(model = name, n = nrow(zz), df = df,
                                          formula = paste(deparse(form), collapse = " "))
  }
  write_table(bind_rows(audit), "reviewed_formulas")
  cells <- read.csv(file.path(out, "categorical_cells.csv"))
  diag <- read.csv(file.path(out, "model_diagnostics.csv"))
  vif <- read.csv(file.path(out, "collinearity.csv"))
  summary <- list(verdict = "pass", n = nrow(z), cases = sum(z$ra == 1),
                  controls = sum(z$ra == 0), asthma = sum(z$asthma),
                  coexisting = sum(z$ra == 1 & z$asthma == 1),
                  pre_covariate_n = sum(before_covariates),
                  excluded_incomplete = sum(before_covariates) - nrow(z),
                  model_count = length(models), all_models_estimable = all(diag$status == "estimable"),
                  warning_models = sum(!is.na(diag$warnings) & nzchar(diag$warnings)),
                  categorical_small_cells = sum(cells$warning_small_cell),
                  maximum_adjusted_GVIF = max(vif$adjusted),
                  minimum_fitted = min(diag$min_fitted), maximum_fitted = max(diag$max_fitted),
                  technical_scope = "saved-frame reconstruction and independent numerical checks",
                  clinical_validation = FALSE, causal_validation = FALSE,
                  pooling_appropriateness = "not established by numerical checks")
  write_json(summary, file.path(audit_dir, "review_gate.json"), auto_unbox = TRUE, pretty = TRUE)
  print(summary)
}
tryCatch(review(), error = function(error) {
  write_json(list(verdict = "revise", error = conditionMessage(error)),
             file.path(audit_dir, "review_gate.json"), auto_unbox = TRUE, pretty = TRUE)
  stop(conditionMessage(error), call. = FALSE)
}, finally = write_table(bind_rows(checks), "numerical_checks"))
