#!/usr/bin/env bash
# Starts an openmavis container. This folder is mounted at /workspace and
# ../Datasets read-only at /datasets.
#   ./docker/run.sh                                  # shell
#   ./docker/run.sh tools/run_hilti.sh exp14_basement_2
#   DATASETS_RW=1 ./docker/run.sh tools/rosbag2euroc.py ...   # writable /datasets
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATASETS="${DATASETS:-$(cd "$ROOT/.." && pwd)/Datasets}"
TAG="${TAG:-26.04}"
MODE=ro; [ "${DATASETS_RW:-0}" = "1" ] && MODE=rw

TTY=(-i); if [ -t 0 ] && [ -t 1 ]; then TTY+=(-t); fi
[ $# -eq 0 ] && set -- /bin/bash

# LIBC_FATAL_STDERR_: glibc aborts ("free(): invalid pointer") go to stderr,
# not /dev/tty, so they land in the run log.
exec docker run --rm "${TTY[@]}" \
  --platform linux/arm64 \
  --shm-size=2g \
  -e LIBC_FATAL_STDERR_=1 \
  -v "${ROOT}:/workspace" \
  -v "${DATASETS}:/datasets:${MODE}" \
  -w /workspace \
  "openmavis:${TAG}" "$@"
