#!/usr/bin/env bash
# ATE (RMSE, SE3 Umeyama alignment, no scale — the trajectories are
# visual-inertial) with evo. Estimate is OpenMAVIS's TUM-format output.
#   tools/eval_ate.sh GT EST tum|euroc
set -euo pipefail
GT="$1"; EST="$2"; FMT="${3:-tum}"
export MPLBACKEND=Agg
evo_ape "$FMT" "$GT" "$EST" -a --t_max_diff 0.02 \
  --save_results ape.zip --no_warnings 2>&1 | grep -vE '^\s*$'
n_est=$(grep -vc '^#' "$EST")
echo "estimated poses: ${n_est}"
