#!/usr/bin/env bash
# Starts a virtual X server so Pangolin can open its window: upstream
# multi_inertial_euroc constructs the System with the viewer always on.
# Set DISPLAY yourself (e.g. XQuartz) to skip Xvfb.
set -euo pipefail

if [ -z "${DISPLAY:-}" ]; then
  export DISPLAY=:99
  if ! xdpyinfo -display :99 >/dev/null 2>&1; then
    Xvfb :99 -screen 0 "${XVFB_RESOLUTION:-1600x1200x24}" -nolisten tcp >/tmp/xvfb.log 2>&1 &
    for _ in $(seq 1 50); do
      xdpyinfo -display :99 >/dev/null 2>&1 && break
      sleep 0.1
    done
  fi
  # llvmpipe: software GL, no host GPU needed.
  export LIBGL_ALWAYS_SOFTWARE=1
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

exec "$@"
