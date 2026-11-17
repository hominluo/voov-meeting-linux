#!/usr/bin/env bash
# VooV Meeting launcher (native client: patched Tencent Meeting for Linux).
#
# The application is Tencent's official Linux client with the VooV patches
# applied (scripts/patch-linux-build.py). It runs natively — no Wine — and
# keeps its state in the standard XDG directories, so the /opt tree stays
# read-only.
set -euo pipefail

self=$(readlink -f -- "$0")
root=$(dirname "$(dirname "$self")")
app=$root/app

if [[ ! -x $app/bin/wemeetapp ]]; then
  echo "VooV Meeting: application files are missing ($app)" >&2
  exit 1
fi

# On Wayland sessions the client must run through XWayland. Its X11 helper
# code (QtX11Extras) breaks under the Qt Wayland platform: QX11Info::display()
# returns the wl_display and the first Xlib call on that path (XInternAtom in
# x_utils::SetStayOnTop, used by the WeChat-login view) segfaults. Environments
# like Omarchy preset QT_QPA_PLATFORM=wayland;xcb, so it is overridden
# unconditionally — the same thing Tencent's official wemeetapp.sh does.
if [[ ${XDG_SESSION_TYPE:-} = wayland ]]; then
  export QT_QPA_PLATFORM=xcb
  export XDG_SESSION_TYPE=x11
  export WEMEET_XWAYLAND=1
  unset WAYLAND_DISPLAY
fi

export LD_LIBRARY_PATH=$app/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export QT_PLUGIN_PATH=$app/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}
export PATH=$app/bin:$PATH

exec "$app/bin/wemeetapp" --target=main "$@"