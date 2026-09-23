#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
analysis_script="$1"
shift
runtime_home="$(R RHOME)"
if [[ "$(uname -s)" == Darwin && -f "$runtime_home/lib/libRblas.vecLib.dylib" ]]; then
  mkdir -p .Rruntime
  if [[ ! -e .Rruntime/libRblas.dylib ]]; then
    ln -s "$runtime_home/lib/libRblas.vecLib.dylib" .Rruntime/libRblas.dylib
  fi
  # Calling the R binary directly preserves the per-process loader setting.
  # This does not change the global R installation or its BLAS symlink.
  exec env R_HOME="$runtime_home" DYLD_LIBRARY_PATH="$project_root/.Rruntime" \
    VECLIB_MAXIMUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
    "$runtime_home/bin/exec/R" --vanilla --slave --file="$analysis_script" --args "$@"
else
  exec env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 Rscript "$analysis_script" "$@"
fi
