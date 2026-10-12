# Unified pooled analysis v03

This version uses the available NHANES releases through August 2023 as one pooled analysis. The standalone entry point does not run period-specific comparisons, period-adjusted models or period interactions. Source-release metadata remain for weight and provenance checks.

## Files

- `scripts/pooled_only_v3/`: exact analysis, diagnostic and post-run review code used for the new results. `run_analysis.sh --check` checks the existing prepared input; `--run` fits and diagnoses the models. Running again refuses to overwrite existing output directories.
- Aggregate results are delivered locally with the report; this branch adds no result tables, participant records or model objects.
- `scripts/client_report_v03/`: source-bound flow diagram, subgroup forest plot, three-page Chinese Word report, rendering wrapper and document verification.
- `scripts/year_extension_v1/prepare.R`: historical preparation implementation, referenced for the disease definitions only. The new entry point does not call its period-specific loops.

The analysis reuses the previously prepared, audited external `analysis_frame.rds` specified in `config.R`. Set paths for your own environment; prerequisite raw-data preparation and dictionaries are in the existing year-extension code. This is a code snapshot conditional on the prepared input, not a claim of a fresh raw-data rebuild.

## Cohort and interpretation

The comparison is self-reported rheumatoid arthritis versus explicitly no arthritis, with ever-diagnosed asthma as the outcome. Adults aged 20–79 with complete prespecified covariates are included. Other arthritis and unknown types are excluded. Four pooled models and the prespecified age/sex subgroup and interaction analyses use the retained complex survey design.

The available-release duration weighting scheme is retained as a study-defined mixture estimand. CDC generally discourages pooling August 2021–August 2023 with earlier cycles because of the collection gap. This run does not resolve that gap assumption or time-related confounding. See the [CDC weighting tutorial](https://wwwn.cdc.gov/nchs/nhanes/tutorials/weighting.aspx). Numerical checks do not establish causation, phenotype validity, absence of selection bias, or unconditional population generalizability.

## Report reproduction

Supply the locally delivered aggregate CSVs under `outputs/pooled_only_20261012_v03/` first. Install `python-docx`, `reportlab` and `pypdf`; make Poppler available on PATH. Supply a CJK TrueType font if not running on macOS. From the repository root:

```bash
python scripts/client_report_v03/build_report.py --code-ref COMMIT_SHA --font-path /path/to/CJK.ttf
python scripts/client_report_v03/render_report.py REPORT.docx --renderer /path/to/render_docx.py --output RENDER_DIR
python scripts/client_report_v03/verify_report.py --code-ref COMMIT_SHA
```

`COMMIT_SHA` must name the published version containing the analysis and figure code, so every report step has a stable file-and-line link. `render_report.py` expects the official document renderer supplied in the authoring environment; another LibreOffice workflow may be used for independent reproduction. Inspect all three final pages after rendering. The report does not add unperformed sensitivity analyses or reproduce historical period results.
