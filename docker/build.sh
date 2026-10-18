#!/usr/bin/env bash
# Builds the openmavis image (base -> pangolin -> openmavis).
#   ./docker/build.sh                 # all stages, cached
#   ./docker/build.sh --no-cache      # full rebuild
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${PLATFORM:-linux/arm64}"
TAG="${TAG:-26.04}"
JOBS="${JOBS:-8}"
docker build --platform "$PLATFORM" \
  --build-arg "JOBS=${JOBS}" \
  -t "openmavis:${TAG}" \
  "$@" "$ROOT/docker"
