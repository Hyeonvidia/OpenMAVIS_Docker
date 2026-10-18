#!/usr/bin/env bash
# Host: runs every (sequence, mode, run) one after another, skipping any run
# that already has a status.txt, so it can be re-invoked to resume.
#   tools/bench_hilti.sh "exp14_basement_2 exp18_corridor_lower_gallery_2" [runs=3]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEQS="${1:?space-separated sequence names}"
RUNS="${2:-3}"
for r in $(seq 1 "$RUNS"); do
  for s in $SEQS; do
    for m in multi stereo; do
      d="$ROOT/results/hilti/$s/$m/r$r"
      if [ -f "$d/status.txt" ]; then echo "skip $s $m r$r"; continue; fi
      echo "== $s $m r$r  $(date +%H:%M:%S)"
      "$ROOT/docker/run.sh" tools/run_hilti.sh "$s" "$m" "r$r" | sed 's/^/   /'
    done
  done
done
