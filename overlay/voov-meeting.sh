#!/usr/bin/env bash
# VooV Meeting launcher.
#
# The application is Tencent's official Windows build running under Wine. The
# package installs it read-only under /opt; VooV writes databases, caches and
# preference files next to its own DLLs, so the first run copies the tree into
# a per-user Wine prefix and every later run reuses it.
set -euo pipefail

self=$(readlink -f -- "$0")
bin_dir=$(dirname "$self")
root=$(dirname "$bin_dir")
app_src=$root/app
version=$(cat "$root/VERSION" 2>/dev/null || echo 0)
app_version=${version%-*}

data=${VOO_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/voov-meeting}
prefix=$data/prefix
inst="$prefix/drive_c/Program Files/Tencent/VooVMeeting"
log=$data/voov-meeting.log

notify() {
  local title=$1 body=${2:-}
  if [[ ! -t 1 ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send -a "VooV Meeting" "$title" "$body" || true
  else
    printf '%s%s\n' "$title" "${body:+ — $body}" >&2
  fi
}

fail() {
  notify "VooV Meeting" "$1"
  if [[ ! -t 1 ]] && command -v zenity >/dev/null 2>&1; then
    zenity --error --title="VooV Meeting" --text="$1" || true
  fi
  exit 1
}

# --- Wine ----------------------------------------------------------------
if [[ -x $root/lib/wine/bin/wine ]]; then
  wine=$root/lib/wine/bin/wine
  export PATH=$root/lib/wine/bin:$PATH
else
  wine=$(command -v wine || command -v wine64 || true)
  [[ -n $wine ]] || fail "Wine is not installed. Install your distribution's wine package and try again."
fi

[[ -d $app_src ]] || fail "The VooV Meeting application files are missing ($app_src)."
[[ -f $app_src/.voov-manifest ]] || fail "The VooV Meeting application files are incomplete ($app_src)."

export WINEPREFIX=$prefix
export WINEARCH=win64
export WINEDEBUG=${WINEDEBUG:--all}
# No Mono/Gecko prompts, no duplicate menu entries: the app uses its own
# embedded browser and this package ships its own desktop file. The mscoree
# override also keeps wineboot from stalling on mscoree.dll registration.
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml="

# --- First run / upgrade -------------------------------------------------
want=$(cat "$app_src/.voov-manifest")
have=$(cat "$data/manifest" 2>/dev/null || true)

mkdir -p "$data"
if [[ ! -d $inst || $want != "$have" ]]; then
  if [[ -d $inst ]]; then
    notify "Updating VooV Meeting" "Reinstalling the client in $prefix"
  else
    notify "Preparing VooV Meeting" "First run: this takes a moment and about 1.5 GB of disk space"
  fi

  if [[ ! -f $prefix/system.reg ]]; then
    "$wine" wineboot -u >>"$log" 2>&1 || fail "Could not create the Wine prefix (see $log)."
  fi

  mkdir -p "$(dirname "$inst")"
  # --reflink=auto is a normal copy where the filesystem cannot reflink.
  rm -rf "$inst.tmp"
  cp -a --reflink=auto "$app_src" "$inst.tmp" 2>/dev/null || {
    rm -rf "$inst.tmp"
    cp -a "$app_src" "$inst.tmp"
  }
  rm -rf "$inst"
  mv "$inst.tmp" "$inst"

  reg() {
    "$wine" reg add "$1" /v "$2" /t "$3" /d "$4" /f >/dev/null 2>&1 || true
  }
  for key in 'HKCU\Software\Tencent\VooVMeeting' 'HKCU\Software\Tencent\WeMeet'; do
    reg "$key" InstallRootDir REG_SZ 'C:\Program Files\Tencent\VooVMeeting'
    reg "$key" enable_intercept REG_DWORD 0
    reg "$key" force_disable_intercept REG_DWORD 1
    reg "$key" enable_force_disable_intercept REG_DWORD 1
  done
  reg 'HKCU\Software\Tencent\VooVMeeting' APPID REG_SZ 1410000197
  reg 'HKCU\Software\Tencent\VooVMeeting' Version REG_SZ "$app_version"

  printf '%s\n' "$want" > "$data/manifest"
fi

# --- Run -----------------------------------------------------------------
cd "$inst"
exec "$wine" 'C:\Program Files\Tencent\VooVMeeting\voovmeetinglauncher.exe' "$@" >>"$log" 2>&1
