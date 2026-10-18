#!/usr/bin/env bash
# In-container: make the OpenMAVIS viewer reachable from macOS, then run a
# command under it.  Called by docker/run_gui.sh.
#
#   gui_launch.sh x11 <cmd...>   DISPLAY is the outer server (XQuartz); a nested
#                                Xephyr window is opened on it and the viewer
#                                draws into that.
#   gui_launch.sh vnc <cmd...>   DISPLAY is the entrypoint's Xvfb; x11vnc exports
#                                it on port 5900 for macOS Screen Sharing.
#
# Why Xephyr: Mesa cannot present directly to XQuartz from the container (no
# MIT-SHM across the VM boundary; the window stays blank). It presents to Xephyr
# locally, and Xephyr repaints on XQuartz with plain XPutImage.
#
# No window manager runs, so both viewer windows open at +0+0 on top of each
# other. A background loop moves the camera-image window beside the map and
# gives the map window keyboard focus.
set -euo pipefail
MODE="${1:?x11|vnc}"; shift
[ $# -gt 0 ] || { echo "usage: $0 x11|vnc <command...>" >&2; exit 2; }
SCREEN="${GUI_SCREEN:-1684x770}"   # map 1024x768 + camera images 648x563 side by side

case "$MODE" in
  x11)
    : "${DISPLAY:?DISPLAY must point at the outer X server}"
    # -no-host-grab: a stray Ctrl+Shift on the host must not capture input.
    # -sw-cursor: otherwise the pointer vanishes inside the window.
    Xephyr :100 -screen "${SCREEN}x24" -title 'OpenMAVIS Viewer' -resizeable \
        -no-host-grab -sw-cursor -nolisten tcp > /tmp/xephyr.log 2>&1 &
    export DISPLAY=:100
    for _ in $(seq 1 50); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done
    xdpyinfo >/dev/null 2>&1 || { echo "Xephyr did not start:" >&2; cat /tmp/xephyr.log >&2; exit 1; }
    ;;
  vnc)
    # A password is required: macOS Screen Sharing never completes the
    # handshake with a server that offers only RFB security type None.
    x11vnc -storepasswd "${VNC_PASSWORD:-openmavis}" /tmp/vncpass >/dev/null 2>&1
    x11vnc -display "$DISPLAY" -forever -shared -rfbauth /tmp/vncpass \
        -rfbport 5900 -quiet -bg -o /tmp/x11vnc.log >/dev/null 2>&1
    ;;
  *) echo "mode must be x11 or vnc" >&2; exit 2 ;;
esac

# Pangolin's X11 backend learns its window size only from ConfigureNotify
# (display_x11.cpp), which normally comes from the window manager. Without one
# it lays the map view out for a 0x0 window: no menu panel, and the 3D view
# squeezed into a corner. Resizing the window once produces the event.
arrange() {
  local placed="" sized=""
  while true; do
    map=$(xdotool search --name 'Map Viewer' 2>/dev/null | head -1 || true)
    frame=$(xdotool search --name 'Current Frame' 2>/dev/null | head -1 || true)
    if [ -n "$map" ] && [ "$map" != "$sized" ]; then
      sleep 0.5
      xdotool windowsize "$map" 1023 767 >/dev/null 2>&1 &&
        xdotool windowsize "$map" 1024 768 >/dev/null 2>&1 && sized=$map
    fi
    if [ -n "$frame" ] && [ "$frame" != "$placed" ]; then
      xdotool windowmove "$frame" 1030 0 >/dev/null 2>&1 && placed=$frame
    fi
    [ -n "$map" ] && xdotool windowfocus "$map" >/dev/null 2>&1 || true
    sleep 1
  done
}
arrange &
ARRANGE_PID=$!
trap 'kill $ARRANGE_PID 2>/dev/null || true' EXIT INT TERM

"$@"
