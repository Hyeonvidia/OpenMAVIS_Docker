#!/usr/bin/env bash
# Runs one command in an openmavis container with the viewer (Pangolin map +
# camera images) visible on the macOS desktop.
#
#   ./docker/run_gui.sh tools/run_hilti.sh exp14_basement_2 multi gui
#   ./docker/run_gui.sh tools/run_hilti.sh exp16_attic_to_upper_gallery_2 stereo gui
#   ./docker/run_gui.sh --vnc tools/run_hilti.sh exp14_basement_2 multi gui
#
#   (default)   XQuartz window 'OpenMAVIS Viewer'. XQuartz must allow network
#               clients (Settings > Security); it is started if not running.
#   --vnc       no XQuartz: macOS Screen Sharing at vnc://localhost:PORT,
#               password 'openmavis' (OPENMAVIS_VNC_PASSWORD overrides)
#   --port N    VNC port on 127.0.0.1, default 5900
#   --no-open   (vnc) print the URL instead of opening Screen Sharing
#
# Rendering is software (llvmpipe) inside the container either way; only the
# finished images cross to macOS. The window closes when the run ends, as
# upstream does. Use a run tag other than r1..r3 so GUI runs stay out of
# tools/summarize_hilti.py.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATASETS="${DATASETS:-$(cd "$ROOT/.." && pwd)/Datasets}"
TAG="${TAG:-26.04}"
MODE=x11; PORT=5900; OPEN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --vnc)     MODE=vnc; shift ;;
    --port)    PORT="$2"; shift 2 ;;
    --no-open) OPEN=0; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

NAME=openmavis-gui
docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM
COMMON=(--rm --name "$NAME" --platform linux/arm64 --shm-size=2g
        -e LIBC_FATAL_STDERR_=1 -e LIBGL_ALWAYS_SOFTWARE=1
        -v "${ROOT}:/workspace" -v "${DATASETS}:/datasets:ro" -w /workspace)

if [ "$MODE" = x11 ]; then
  if ! pgrep -qx Xquartz 2>/dev/null; then
    echo "== starting XQuartz"; open -a XQuartz
    for _ in $(seq 1 30); do pgrep -qx Xquartz 2>/dev/null && break; sleep 1; done
  fi
  pgrep -qx Xquartz 2>/dev/null || { echo "XQuartz is not available; use --vnc" >&2; exit 1; }
  # The container reaches XQuartz over TCP.
  /opt/X11/bin/xhost +localhost >/dev/null 2>&1 || true
  echo "== window 'OpenMAVIS Viewer' opens on XQuartz; Ctrl-C stops the run"
  # Mesa's "Failed to attach to x11 shm" is expected once per frame on the
  # outer connection only and is filtered out.
  docker run "${COMMON[@]}" -e DISPLAY=host.docker.internal:0 "openmavis:${TAG}" \
    /workspace/docker/gui_launch.sh x11 "$@" 2>&1 | grep -v "Failed to attach to x11 shm"
  exit "${PIPESTATUS[0]}"
fi

PASS="${OPENMAVIS_VNC_PASSWORD:-openmavis}"
SCREEN="${GUI_SCREEN:-1684x770}"
docker run -d "${COMMON[@]}" -p "127.0.0.1:${PORT}:5900" \
  -e "VNC_PASSWORD=${PASS}" -e "XVFB_RESOLUTION=${SCREEN}x24" \
  "openmavis:${TAG}" /workspace/docker/gui_launch.sh vnc "$@" >/dev/null
for _ in $(seq 1 60); do
  nc -z 127.0.0.1 "$PORT" 2>/dev/null && break
  docker ps -q -f "name=$NAME" | grep -q . || { echo "container exited early:"; docker logs "$NAME" 2>&1 | tail -20; exit 1; }
  sleep 0.5
done
nc -z 127.0.0.1 "$PORT" 2>/dev/null || { echo "VNC port ${PORT} never opened" >&2; exit 1; }
echo "== VNC ready at vnc://localhost:${PORT}   password: ${PASS}"
if [ "$OPEN" = 1 ]; then open "vnc://localhost:${PORT}"; else echo "== open it with:  open vnc://localhost:${PORT}"; fi
echo "== Ctrl-C stops the run"
docker logs -f "$NAME" 2>&1 || true
