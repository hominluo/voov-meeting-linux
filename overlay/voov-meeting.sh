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

# On Wayland sessions the client runs through XWayland, matching the official
# launcher (its Wayland path needs Tencent's own x11-wayland integration).
if [[ ${XDG_SESSION_TYPE:-} = wayland && -z ${QT_QPA_PLATFORM:-} ]]; then
  export QT_QPA_PLATFORM=xcb
fi

export LD_LIBRARY_PATH=$app/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export QT_PLUGIN_PATH=$app/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}
export PATH=$app/bin:$PATH

exec "$app/bin/wemeetapp" --target=main "$@"