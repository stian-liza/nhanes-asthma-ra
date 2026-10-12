# 合并分析 v03：由独立入口调用，不运行旧的分时期或周期调整脚本。
source("scripts/pooled_only_v3/config.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1 || !args %in% c("--check", "--run")) {
  stop("用法：bash scripts/pooled_only_v3/run_analysis.sh --check 或 --run")
}
checked <- check_input()
if (args == "--check") quit(status = 0)
if (dir.exists(out) || dir.exists(diagnostic_dir)) {
  stop("新版输出目录已存在，为避免覆盖请先另存结果并配置新的输出路径。")
}
stopifnot(dir.create(out, recursive = TRUE),
          dir.create(diagnostic_dir, recursive = TRUE))
write_json(list(verdict = "running", result_ready = FALSE),
           file.path(out, "run_gate.json"), auto_unbox = TRUE, pretty = TRUE)
write_json(list(scope = "pooled available releases through 2023; no period adjustment",
                input_md5 = checked$input_md5, timestamp = as.character(Sys.time())),
           file.path(out, "input_binding.json"), auto_unbox = TRUE, pretty = TRUE)
write_result <- function(x, name) {
  write.csv(x, file.path(out, paste0(name, ".csv")), row.names = FALSE, na = "")
}
d <- checked$frame
observed_cycle_starts <- sort(unique(as.integer(d$year)))

broad <- d[d$design_valid, ]

# Do not concatenate cycle and stratum. The official 1999-2002 strata overlap
# by design. The analysis uses one pooled survey design and one pooled domain.
wide <- svydesign(
  ids = ~SDMVPSU,
  strata = ~SDMVSTRA,
  weights = ~analysis_weight,
  data = broad,
  nest = TRUE
)
des <- subset(wide, eligible)
actual <- des$variables

support <- function(ds, label) {
  z <- ds$variables
  pairs <- unique(z[, c('SDMVSTRA', 'SDMVPSU')])
  psu_per_stratum <- table(pairs$SDMVSTRA)
  data.frame(
    domain = label,
    n = nrow(z),
    strata = length(psu_per_stratum),
    psu = nrow(pairs),
    df = degf(ds),
    strata_with_one_domain_psu = sum(psu_per_stratum == 1),
    weight_sum = sum(z$analysis_weight),
    min_weight = min(z$analysis_weight),
    max_weight = max(z$analysis_weight)
  )
}

audit <- bind_rows(
  support(wide, 'broad_MEC'),
  support(des, 'complete_case')
)
stopifnot(audit$strata_with_one_domain_psu[1] == 0, degf(des) > 0)
write_result(audit, 'design_audit')

# Audit only: this table checks source-cycle coverage and PSU support. It is not
# a period-stratified scientific result and year is not included in any model.
design_source_audit <- broad %>%
  group_by(year, SDMVSTRA) %>%
  summarise(psu = n_distinct(SDMVPSU), n = n(), .groups = 'drop')
write_result(design_source_audit, 'design_source_cycle_audit')

write_result(
  actual %>% count(SDMVSTRA, SDMVPSU, ra, asthma, name = 'n'),
  'domain_psu_counts'
)

# Pooled prevalence estimates with design-based logit confidence intervals.
prevalence_rows <- list()
for (group_name in c('All', 'No_arthritis', 'RA')) {
  group_design <- if (group_name == 'All') {
    des
  } else {
    subset(des, ra == ifelse(group_name == 'RA', 1, 0))
  }
  z <- group_design$variables
  estimate <- as.numeric(coef(svymean(~asthma, group_design)))
  manual <- sum(z$analysis_weight * z$asthma) / sum(z$analysis_weight)
  stopifnot(abs(estimate - manual) < 1e-12)

  ci <- c(NA_real_, NA_real_)
  status <- 'estimable'
  if (estimate > 0 && estimate < 1 && degf(group_design) > 0) {
    ci_object <- try(
      svyciprop(~asthma, group_design, method = 'logit', df = degf(group_design)),
      silent = TRUE
    )
    if (inherits(ci_object, 'try-error')) {
      status <- 'CI_not_estimable'
    } else {
      ci <- as.numeric(confint(ci_object))
    }
  } else {
    status <- 'CI_not_estimable'
  }

  prevalence_rows[[length(prevalence_rows) + 1]] <- data.frame(
    group = group_name,
    n = nrow(z),
    events = sum(z$asthma),
    estimate = estimate,
    lower = ci[1],
    upper = ci[2],
    df = degf(group_design),
    method = 'survey logit CI',
    status = status,
    manual_difference = estimate - manual
  )
}
write_result(bind_rows(prevalence_rows), 'asthma_prevalence')

# Pooled descriptive table.
characteristics <- list()
quantiles <- list()
for (group_name in c('All', 'No_arthritis', 'RA')) {
  group_design <- if (group_name == 'All') {
    des
  } else {
    subset(des, ra == ifelse(group_name == 'RA', 1, 0))
  }
  z <- group_design$variables

  for (variable in c('age', 'bmi', 'pir')) {
    mean_object <- svymean(reformulate(variable), group_design)
    characteristics[[length(characteristics) + 1]] <- data.frame(
      group = group_name,
      variable = variable,
      level = 'continuous',
      n = nrow(z),
      estimate = as.numeric(coef(mean_object)),
      se = as.numeric(SE(mean_object)),
      method = 'weighted_mean'
    )

    quantile_object <- svyquantile(
      reformulate(variable),
      group_design,
      quantiles = c(.25, .5, .75),
      ci = FALSE,
      qrule = 'math'
    )
    quantiles[[length(quantiles) + 1]] <- data.frame(
      group = group_name,
      variable = variable,
      q25 = as.numeric(coef(quantile_object))[1],
      median = as.numeric(coef(quantile_object))[2],
      q75 = as.numeric(coef(quantile_object))[3],
      method = 'survey weighted quantile qrule math'
    )
  }

  for (variable in c('agegroup', 'sex', 'race', 'education',
                     'pirgroup', 'bmigroup', 'smoking')) {
    proportion_object <- svymean(reformulate(variable), group_design)
    for (level_index in seq_along(levels(z[[variable]]))) {
      level_name <- levels(z[[variable]])[level_index]
      characteristics[[length(characteristics) + 1]] <- data.frame(
        group = group_name,
        variable = variable,
        level = level_name,
        n = sum(z[[variable]] == level_name),
        estimate = as.numeric(coef(proportion_object))[level_index],
        se = as.numeric(SE(proportion_object))[level_index],
        method = 'weighted_proportion'
      )
    }
  }
}
write_result(bind_rows(characteristics), 'characteristics')
write_result(bind_rows(quantiles), 'continuous_quantiles')

# Design-corrected categorical comparisons. These tests are descriptive and do
# not select covariates for regression.
tests <- list()
covariate_table <- list()
sparse_cells <- list()
for (outcome in c('asthma', 'ra')) {
  for (variable in c('agegroup', 'sex', 'race', 'education',
                     'pirgroup', 'bmigroup', 'smoking')) {
    test_formula <- as.formula(paste('~', variable, '+', outcome))
    test_object <- svychisq(test_formula, des, statistic = 'F')
    tests[[length(tests) + 1]] <- data.frame(
      outcome = outcome,
      variable = variable,
      F = unname(test_object$statistic),
      df1 = test_object$parameter[1],
      df2 = test_object$parameter[2],
      p = test_object$p.value,
      method = test_object$method
    )

    for (level_name in levels(actual[[variable]])) {
      level_design <- des[actual[[variable]] == level_name, ]
      z <- level_design$variables
      mean_object <- svymean(reformulate(outcome), level_design)
      covariate_table[[length(covariate_table) + 1]] <- data.frame(
        outcome = outcome,
        variable = variable,
        level = level_name,
        n = nrow(z),
        events = sum(z[[outcome]]),
        estimate = as.numeric(coef(mean_object)),
        se = as.numeric(SE(mean_object))
      )
      sparse_cells[[length(sparse_cells) + 1]] <- data.frame(
        outcome = outcome,
        variable = variable,
        level = level_name,
        events = sum(z[[outcome]]),
        nonevents = sum(1 - z[[outcome]]),
        warning_small_cell = min(sum(z[[outcome]]), sum(1 - z[[outcome]])) < 5
      )
    }
  }
}
write_result(bind_rows(tests), 'covariate_tests')
combined_covariates <- bind_rows(covariate_table)
write_result(filter(combined_covariates, outcome == 'asthma'), 'covariates_asthma')
write_result(filter(combined_covariates, outcome == 'ra'), 'covariates_ra')
write_result(bind_rows(sparse_cells), 'categorical_cells')

# Prespecified pooled regression models. No year, cycle, period, or era term is
# included, and no data-dependent variable selection is performed.
models <- list()
diagnostics <- list()
coefficients <- list()
model_cells <- list()
domain_support <- list()

fit_one <- function(ds, formula, label) {
  assert_formula(formula)
  z <- ds$variables
  warnings <- character()
  design_df <- degf(ds)

  cell_table <- as.data.frame(table(ra = z$ra, asthma = z$asthma))
  names(cell_table)[3] <- 'n'
  cell_table$model <- label
  model_cells[[length(model_cells) + 1]] <<- cell_table
  domain_support[[length(domain_support) + 1]] <<- support(ds, label)

  model_matrix <- model.matrix(formula, z)
  diagnostic_matrix <- model_matrix[, -1, drop = FALSE]
  diagnostic_sd <- apply(diagnostic_matrix, 2, sd)
  informative_columns <- is.finite(diagnostic_sd) & diagnostic_sd > 0
  condition_number <- if (any(informative_columns)) {
    tryCatch(
      kappa(scale(diagnostic_matrix[, informative_columns, drop = FALSE]),
            exact = TRUE),
      error = function(error) NA_real_
    )
  } else {
    NA_real_
  }

  fit <- withCallingHandlers(
    tryCatch(
      svyglm(
        formula,
        ds,
        family = quasibinomial(),
        control = glm.control(maxit = 100, epsilon = 1e-12)
      ),
      error = function(error) error
    ),
    warning = function(warning) {
      warnings <<- c(warnings, conditionMessage(warning))
      invokeRestart('muffleWarning')
    }
  )

  if (inherits(fit, 'error')) {
    diagnostics[[length(diagnostics) + 1]] <<- data.frame(
      model = label,
      n = nrow(z),
      events = sum(z$asthma),
      df = design_df,
      rank = qr(model_matrix)$rank,
      columns = ncol(model_matrix),
      condition_number = condition_number,
      converged = FALSE,
      iterations = NA,
      max_abs_beta = NA,
      max_se = NA,
      min_fitted = NA,
      max_fitted = NA,
      status = 'not_estimable',
      warnings = conditionMessage(fit)
    )
    return(data.frame(
      model = label,
      term = 'ra',
      n = nrow(z),
      events = sum(z$asthma),
      beta = NA_real_,
      se = NA_real_,
      OR = NA_real_,
      lower = NA_real_,
      upper = NA_real_,
      p = NA_real_,
      df = design_df,
      status = 'not_estimable',
      formula = paste(deparse(formula), collapse = ' ')
    ))
  }

  beta <- coef(fit)
  standard_error <- sqrt(diag(vcov(fit)))
  valid <- fit$converged &&
    qr(model_matrix)$rank == ncol(model_matrix) &&
    all(is.finite(beta)) &&
    all(is.finite(standard_error)) &&
    design_df > 0

  # The same matrices are saved for a separate linear-programming separation
  # diagnostic. Until that check passes, model status remains pending.
  saveRDS(
    list(X = model_matrix, y = z$asthma),
    file.path(diagnostic_dir, paste0('separation_', label, '.rds'))
  )

  diagnostics[[length(diagnostics) + 1]] <<- data.frame(
    model = label,
    n = nrow(z),
    events = sum(z$asthma),
    df = design_df,
    rank = qr(model_matrix)$rank,
    columns = ncol(model_matrix),
    condition_number = condition_number,
    converged = fit$converged,
    iterations = fit$iter,
    max_abs_beta = max(abs(beta)),
    max_se = max(standard_error),
    min_fitted = min(fitted(fit)),
    max_fitted = max(fitted(fit)),
    status = ifelse(valid, 'pending_separation_check', 'not_estimable'),
    warnings = paste(unique(warnings), collapse = ' | ')
  )

  margin <- qt(.975, design_df) * standard_error
  p_value <- 2 * pt(abs(beta / standard_error), design_df, lower.tail = FALSE)
  summary_p <- summary(fit, df.resid = design_df)$coefficients[, 4]
  summary_p <- summary_p[names(p_value)]
  finite_p <- is.finite(p_value) & is.finite(summary_p)
  if (any(finite_p)) {
    stopifnot(max(abs(p_value[finite_p] - summary_p[finite_p])) < 1e-12)
  }

  result <- data.frame(
    model = label,
    term = names(beta),
    n = nrow(z),
    events = sum(z$asthma),
    beta = beta,
    se = standard_error,
    OR = exp(beta),
    lower = exp(beta - margin),
    upper = exp(beta + margin),
    p = p_value,
    df = design_df,
    status = ifelse(valid, 'pending_separation_check', 'not_estimable'),
    formula = paste(deparse(formula), collapse = ' '),
    row.names = NULL
  )
  coefficients[[length(coefficients) + 1]] <<- result
  models[[label]] <<- fit
  result[result$term == 'ra', ]
}

regression <- bind_rows(
  lapply(names(forms), function(model_name) {
    fit_one(des, forms[[model_name]], model_name)
  })
)
stopifnot(length(unique(regression$n)) == 1)

# Prespecified age and sex subgroup analyses on the same pooled dataset.
subgroups <- list()
for (subgroup_variable in c('agegroup', 'sex')) {
  for (subgroup_level in levels(actual[[subgroup_variable]])) {
    subgroup_design <- des[actual[[subgroup_variable]] == subgroup_level, ]
    subgroup_formula <- if (subgroup_variable == 'sex') {
      update(forms$M3, . ~ . - sex)
    } else {
      forms$M3
    }
    label <- paste0(subgroup_variable, '_', gsub('-', '_', subgroup_level))
    subgroup_result <- fit_one(subgroup_design, subgroup_formula, label)
    if (!is.null(subgroup_result)) {
      subgroup_result$subgroup_variable <- subgroup_variable
      subgroup_result$subgroup <- subgroup_level
      subgroups[[length(subgroups) + 1]] <- subgroup_result
    }
  }
}

# Interaction tests assess age- and sex-related effect modification only. They
# do not compare survey periods.
interactions <- list()
for (interaction_variable in c('agegroup', 'sex')) {
  interaction_formula <- if (interaction_variable == 'agegroup') {
    update(forms$M3, . ~ . + agegroup + ra:agegroup)
  } else {
    update(forms$M3, . ~ . + ra:sex)
  }
  label <- paste0('interaction_', interaction_variable)
  fit_one(des, interaction_formula, label)
  interaction_model <- models[[label]]
  test_object <- NULL
  if (!is.null(interaction_model)) {
    interaction_term <- as.formula(paste0('~ra:', interaction_variable))
    test_object <- try(regTermTest(
      interaction_model,
      interaction_term,
      df = degf(des),
      method = 'Wald'
    ), silent = TRUE)
  }
  test_valid <- !is.null(test_object) && !inherits(test_object, 'try-error')
  interactions[[length(interactions) + 1]] <- data.frame(
      variable = interaction_variable,
      n = nrow(actual),
      F = if (test_valid) as.numeric(test_object$Ftest) else NA_real_,
      df1 = if (test_valid) test_object$df else NA_real_,
      df2 = if (test_valid) test_object$ddf else NA_real_,
      p = if (test_valid) as.numeric(test_object$p) else NA_real_,
      method = 'joint design Wald F; denominator=domain design df'
    )
}

write_result(regression, 'regression')
write_result(bind_rows(subgroups), 'subgroups')
write_result(bind_rows(interactions), 'interaction_tests')
write_result(bind_rows(coefficients), 'all_model_coefficients')
write_result(bind_rows(diagnostics), 'model_diagnostics')
write_result(bind_rows(model_cells), 'model_ra_asthma_cells')
write_result(bind_rows(domain_support), 'model_design_support')
write_result(as.data.frame(cor(actual[, c('age', 'bmi', 'pir')])),
             'continuous_correlations')

# Generalized VIF is a diagnostic only; it does not determine model inclusion.
vifs <- list()
for (model_name in names(models)) {
  model_object <- models[[model_name]]
  if (length(attr(terms(model_object), 'term.labels')) < 2 ||
      grepl('interaction', model_name)) {
    next
  }
  vif_object <- try(car::vif(model_object), silent = TRUE)
  if (!inherits(vif_object, 'try-error')) {
    if (is.matrix(vif_object)) {
      vifs[[length(vifs) + 1]] <- data.frame(
        model = model_name,
        term = rownames(vif_object),
        GVIF = vif_object[, 1],
        Df = vif_object[, 2],
        adjusted = vif_object[, 3],
        row.names = NULL
      )
    } else {
      vifs[[length(vifs) + 1]] <- data.frame(
        model = model_name,
        term = names(vif_object),
        GVIF = as.numeric(vif_object),
        Df = 1,
        adjusted = sqrt(as.numeric(vif_object))
      )
    }
  }
}
write_result(bind_rows(vifs), 'collinearity')

saveRDS(models, file.path(diagnostic_dir, 'models.rds'))
writeLines(capture.output(sessionInfo()), file.path(out, 'environment.txt'))

write_json(
  list(
    analysis_scope = 'all included cycles pooled; no period comparison',
    included_cycle_starts = observed_cycle_starts,
    period_variable_in_models = FALSE,
    G4 = 'pass',
    G5 = 'needs separation diagnostic',
    G6 = 'needs separation diagnostic',
    n = nrow(actual),
    events = sum(actual$asthma),
    ra = sum(actual$ra),
    df = degf(des),
    broad_n = nrow(broad)
  ),
  file.path(out, 'analysis_gate.json'),
  auto_unbox = TRUE,
  pretty = TRUE
)

print(regression[, c('model', 'n', 'OR', 'lower', 'upper', 'p')])
print(bind_rows(interactions))
