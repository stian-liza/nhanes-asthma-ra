#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${NHANES_PYTHON:=python3}"
SCRIPT=scripts/year_extension_v1
"$NHANES_PYTHON" "$SCRIPT/acquire.py" metadata
"$NHANES_PYTHON" "$SCRIPT/audit_metadata.py"
"$NHANES_PYTHON" "$SCRIPT/acquire.py" data
"$NHANES_PYTHON" "$SCRIPT/questionnaires.py"
Rscript "$SCRIPT/prepare.R"
Rscript "$SCRIPT/verify_inputs.R"
for scope in prepandemic latest pooled; do
  Rscript "$SCRIPT/analyze.R" "$scope"
  Rscript "$SCRIPT/diagnose.R" "$scope"
  Rscript "$SCRIPT/validate_results.R" "$scope"
done
for scope in prepandemic latest; do
  Rscript "$SCRIPT/supplement.R" "$scope"
  Rscript "$SCRIPT/validate_supplement.R" "$scope"
  Rscript "$SCRIPT/figures.R" "$scope"
done
Rscript "$SCRIPT/pooling.R"
Rscript "$SCRIPT/validate_pooling.R"
"$NHANES_PYTHON" "$SCRIPT/build_report.py"
"$NHANES_PYTHON" "$SCRIPT/validate_report.py"
