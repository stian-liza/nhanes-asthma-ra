# 本版本唯一配置：全部可用年份统一分析，模型不包含时期或周期项。
.libPaths(c("outputs/original_proposal_20260928_v01/R_library", ".Rlib", .libPaths()))
packages <- c("survey", "dplyr", "jsonlite", "car", "lpSolve")
missing_packages <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages)) stop("缺少程序包：", paste(missing_packages, collapse = ", "))
suppressPackageStartupMessages({library(survey); library(dplyr); library(jsonlite)})
options(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE)

root <- "/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1/pooled"
prep_out <- "outputs/year_extension_20261008_v01/pooled"
out <- "outputs/pooled_only_20261012_v03"
diagnostic_dir <- file.path(root, "derived", "pooled_only_20261012_v03")
expected_cycle_starts <- c(1999L, 2001L, 2003L, 2005L, 2007L, 2009L,
                           2011L, 2013L, 2015L, 2017L, 2021L)
forms <- list(
  M0 = asthma ~ ra,
  M1 = asthma ~ ra + age + sex + race,
  M2 = asthma ~ ra + age + sex + race + education + pir,
  M3 = asthma ~ ra + age + sex + race + education + pir + bmi + smoking
)
assert_formula <- function(formula) {
  allowed <- c("asthma", "ra", "age", "sex", "race", "education", "pir",
               "bmi", "smoking", "agegroup")
  if (!all(all.vars(formula) %in% allowed)) stop("模型包含未授权变量：", deparse(formula))
  invisible(TRUE)
}
invisible(lapply(forms, assert_formula))

# 只读检查：核对现有合并数据、定义和已保存的输入审核记录，不运行模型。
check_input <- function() {
  paths <- c(
    frame = file.path(root, "derived", "analysis_frame.rds"),
    preparation = file.path(prep_out, "preparation_gate.json"),
    validation = file.path(prep_out, "independent_input_validation.json"),
    catalog = "outputs/year_extension_20261008_v01/cycle_catalog.csv"
  )
  if (!all(file.exists(paths))) stop("缺少输入，请挂载移动硬盘并检查：",
                                     paste(paths[!file.exists(paths)], collapse = ", "))
  prep <- fromJSON(paths["preparation"])
  validation <- fromJSON(paths["validation"])
  stopifnot(identical(prep$verdict, "pass"), identical(validation$verdict, "pass"))
  frame <- readRDS(paths["frame"])
  required <- c("SEQN", "year", "SDDSRVYR", "analysis_weight", "official_mec_weight",
                "SDMVSTRA", "SDMVPSU", "eligible", "design_valid", "age", "agegroup",
                "asthma", "asthma_status", "ra", "arthritis_status", "sex", "race",
                "education", "pir", "bmi", "smoking", "pirgroup", "bmigroup")
  stopifnot(all(required %in% names(frame)), !anyDuplicated(frame$SEQN),
            !anyNA(frame$SEQN), is.logical(frame$eligible), !anyNA(frame$eligible),
            is.logical(frame$design_valid), !anyNA(frame$design_valid),
            !anyNA(frame$year),
            identical(sort(unique(as.integer(frame$year))), expected_cycle_starts))
  catalog <- read.csv(paths["catalog"], fileEncoding = "UTF-8-BOM")
  stopifnot(identical(as.integer(catalog$year), expected_cycle_starts))
  idx <- match(frame$year, catalog$year)
  # 保留既有23.2年观测时长加权方案；1999和2001共用四年权重。
  # 这是与既定输入方案的一致性检查，不是新的官方合并推荐。
  expected_weight <- frame$official_mec_weight * catalog$duration[idx] / 23.2
  valid <- frame$design_valid
  stopifnot(all(frame$SDDSRVYR == catalog$survey_code[idx]),
            all(is.finite(frame$analysis_weight[valid])),
            all(frame$analysis_weight[valid] > 0),
            all(is.finite(expected_weight[valid])),
            all(abs(frame$analysis_weight[valid] - expected_weight[valid]) <=
                1e-10 * pmax(1, abs(expected_weight[valid]))),
            !anyNA(frame$SDMVSTRA[valid]), !anyNA(frame$SDMVPSU[valid]),
            all(valid[frame$eligible]))
  z <- frame[frame$eligible, ]
  stopifnot(nrow(frame) == prep$n_demo, nrow(z) == prep$n_eligible,
            nrow(z) == validation$n, nrow(z) > 0,
            all(z$age >= 20 & z$age <= 79),
            all(z$ra %in% c(0, 1)), all(z$asthma %in% c(0, 1)),
            all(z$arthritis_status == ifelse(z$ra == 1, "RA", "no_arthritis")),
            all(z$asthma_status == ifelse(z$asthma == 1, "yes", "no")),
            all(complete.cases(z[, c(all.vars(forms$M3), "agegroup", "pirgroup", "bmigroup")])),
            all(vapply(z[c("agegroup", "sex", "race", "education", "smoking",
                           "pirgroup", "bmigroup")], is.factor, logical(1))))
  message("输入检查通过：", length(expected_cycle_starts), "个发布块；合格人数", nrow(z),
          "；模型无周期调整项。尚未拟合模型。")
  list(frame = frame, paths = paths, input_md5 = as.list(tools::md5sum(paths)))
}

