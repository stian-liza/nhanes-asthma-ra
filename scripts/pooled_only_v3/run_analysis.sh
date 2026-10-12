#!/usr/bin/env bash
# 独立入口：默认只检查输入，--run 才执行建模及诊断。
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# -gt 1 ]]; then
  echo '用法：run_analysis.sh [--check|--run]' >&2
  exit 2
fi
case "${1:---check}" in
  --check)
    Rscript scripts/pooled_only_v3/analyze.R --check
    Rscript scripts/pooled_only_v3/diagnose.R --self-test
    ;;
  --run)
    Rscript scripts/pooled_only_v3/analyze.R --run
    Rscript scripts/pooled_only_v3/diagnose.R --run
    ;;
  *)
    echo '用法：run_analysis.sh [--check|--run]；不接受分时期参数。' >&2
    exit 2
    ;;
esac
