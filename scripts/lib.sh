#!/usr/bin/env bash
# Shared configuration and helpers for the VooV Meeting build scripts.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$ROOT/build}
DIST_DIR=${DIST_DIR:-$ROOT/dist}
VENDOR_DIR=${VENDOR_DIR:-$ROOT/vendor}
TREE=$BUILD_DIR/tree
APP_TREE=$TREE/app

APP_ID=voov-meeting
APP_NAME="VooV Meeting"

# Release versioning (see RELEASING.md):
#   the version is the VooV Meeting product version, with our own build
#   counter in parentheses: 3.43.0.510 (1), 3.43.0.510 (2), ...
# Package managers cannot use spaces/parentheses, so packages and tags use
# 3.43.0.510-1 / v3.43.0.510-1 instead.
VOO_V_VERSION=3.43.0.510
BUILD_NUMBER=1
APP_VERSION=$VOO_V_VERSION
RELEASE_NAME="$VOO_V_VERSION ($BUILD_NUMBER)"
PKG_VERSION="$VOO_V_VERSION-$BUILD_NUMBER"

# Official VooV Meeting for Windows, the application we run under Wine.
# The download URL comes from VooV's own download API:
#   https://voovmeeting.com/web-service/query-download-info?q=...&nonce=...
# with {"package-type":"app","channel":"1410000197","platform":"windows",
#       "arch":"x86_64","decorators":["intl"]}.
VOO_CHANNEL=1410000197
VOO_EXE=VooVMeeting_${VOO_CHANNEL}_${VOO_V_VERSION}_x86_64.publish.exe
VOO_EXE_SIZE=281696512
VOO_EXE_MD5=a8d7f83c02853ae055ae5f9cfdcae781
VOO_EXE_SHA256=92649c45d6d46e38bdf0142bb9884f8c69a9cf4013c8816ce3a200dc60a330fc
VOO_EXE_URL=https://updatecdn.meeting.qq.com/cos/$VOO_EXE_MD5/$VOO_EXE

# The macOS build is not shipped, but its icon is the VooV branding used by
# this project (the Windows installer carries no usable icon).
VOO_DMG=VooVMeeting_1410000198_${VOO_V_VERSION}.publish.x86_64.dmg
VOO_DMG_SIZE=245494002
VOO_DMG_MD5=09ec308a02c61e0ede83ffac486e5cea

# Portable Wine, used by the AppImage and Flatpak builds (the .deb, .rpm and
# Arch packages use the distribution's Wine). Upstream:
# https://github.com/Kron4ek/Wine-Builds
WINE_VERSION=11.22
WINE_TARBALL=wine-$WINE_VERSION-amd64.tar.xz
WINE_SHA256=cdaaa76c218359d486eb35968892a4c466623b137ed0931ee3f31465ec6539e0
WINE_URL=https://github.com/Kron4ek/Wine-Builds/releases/download/$WINE_VERSION/$WINE_TARBALL

# Standalone 7-Zip, used to unpack the NSIS-based Windows installer.
SEVENZ_TARBALL=7z2501-linux-x64.tar.xz
SEVENZ_SHA256=4ca3b7c6f2f67866b92622818b58233dc70367be2f36b498eb0bdeaaa44b53f4
SEVENZ_URL=https://www.7-zip.org/a/$SEVENZ_TARBALL

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }

# cp -al when possible: the app tree is ~800 MB and gets staged several times.
# Staged files are never modified in place, so hard links are safe.
hardlink_copy() {
  local src=$1 dst=$2
  rm -rf "$dst"
  cp -al "$src" "$dst" 2>/dev/null || cp -a "$src" "$dst"
}

# Copy for the runtime tree. Reflinks make the per-user app copy nearly free on
# btrfs/XFS; on other filesystems GNU cp falls back to a normal copy.
reflink_copy() {
  local src=$1 dst=$2
  rm -rf "$dst"
  cp -a --reflink=auto "$src" "$dst" 2>/dev/null || cp -a "$src" "$dst"
}

ensure_tree() {
  if [[ ! -f $APP_TREE/.voov-manifest ]]; then
    "$ROOT/scripts/prepare.sh" "$@"
  fi
}

# ensure_wine_tree: extract the portable Wine build into $TREE/wine.
ensure_wine_tree() {
  "$ROOT/scripts/fetch-wine.sh"
}

# AppImage and Flatpak ship Wine themselves; they need it staged.
ensure_bundled_wine() {
  ensure_wine_tree
}

# stage_common <root>: launcher plus the version marker it compares on upgrade.
stage_common() {
  local dest=$1
  install -Dm755 "$ROOT/overlay/voov-meeting.sh" "$dest/opt/voov-meeting/bin/voov-meeting"
  printf '%s\n' "$PKG_VERSION" > "$dest/opt/voov-meeting/VERSION"
}
