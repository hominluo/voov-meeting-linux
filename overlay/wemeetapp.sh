#!/bin/bash
# Launcher for the VooV Meeting Linux build.
#
# Replaces Tencent's original wemeetapp.sh, which forced LC_ALL=zh_CN.UTF-8
# (often not generated on non-Chinese systems) and TZ=Asia/Shanghai.

SELF=$(readlink -f "$0")
HERE=${SELF%/*}
cd "$HERE" || exit 1

export PATH="${HERE}/bin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="${HERE}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="${HERE}/plugins"

# The client is X11-only. Under a Wayland session run it through XWayland.
# The app itself switches to the Wayland platform when it sees a Wayland
# session, so unset both WAYLAND_DISPLAY and the session type as well.
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && [ "${QT_QPA_PLATFORM:-xcb}" = "xcb" ]; then
  if [ -f /opt/x11-wayland/x11-ext.sh ]; then
    # shellcheck source=/dev/null
    . /opt/x11-wayland/x11-ext.sh
  else
    export QT_QPA_PLATFORM=xcb
    export XDG_SESSION_TYPE=x11
    unset WAYLAND_DISPLAY
    export WEMEET_XWAYLAND=1
  fi
fi

exec "${HERE}/bin/wemeetapp" "$@"
