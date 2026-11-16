#!/usr/bin/env bash
# Shared configuration and helpers for the VooV Meeting build scripts.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$ROOT/build}
DIST_DIR=${DIST_DIR:-$ROOT/dist}
VENDOR_DIR=${VENDOR_DIR:-$ROOT/vendor}
TREE=$BUILD_DIR/tree          # patched application tree (contents of /opt/wemeet)
APP_TREE=$TREE

APP_ID=voov-meeting
APP_NAME="VooV Meeting"

# Release versioning (see RELEASING.md):
#   the version is the Tencent Meeting for Linux base version this project is
#   built from, with our own build counter in parentheses:
#   3.26.10.401 (1), 3.26.10.401 (2), ...
# Package managers cannot use spaces/parentheses, so packages and tags use
# 3.26.10.401-1 / v3.26.10.401-1 instead.
TM_VERSION=3.26.10.401
BUILD_NUMBER=1
APP_VERSION=$TM_VERSION
RELEASE_NAME="$TM_VERSION ($BUILD_NUMBER)"
PKG_VERSION="$TM_VERSION-$BUILD_NUMBER"

# Official Tencent Meeting for Linux (China channel 0300000000), the
# application this project patches into VooV. The URL is Tencent's update CDN;
# Content-Length matches TM_DEB_SIZE (verified 2026-11-16).
TM_DEB=TencentMeeting_0300000000_${TM_VERSION}_x86_64_default.publish.officialwebsite.deb
TM_DEB_SIZE=197268516
TM_DEB_MD5=72e0e0023e1d1e6d4123fba28821aea1
TM_DEB_SHA256=70f37b029209c0ef91be9813eebf6650c6cb9a00f7c718490158773e2fe6acaf
TM_DEB_URL=https://updatecdn.meeting.qq.com/cos/$TM_DEB_MD5/$TM_DEB

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }

# cp -al when possible: the app tree is ~700 MB and gets staged several times.
# Staged files are never modified in place, so hard links are safe.
hardlink_copy() {
  local src=$1 dst=$2
  rm -rf "$dst"
  cp -al "$src" "$dst" 2>/dev/null || cp -a "$src" "$dst"
}

# Copy for runtime trees. Reflinks make copies nearly free on btrfs/XFS; on
# other filesystems GNU cp falls back to a normal copy.
reflink_copy() {
  local src=$1 dst=$2
  rm -rf "$dst"
  cp -a --reflink=auto "$src" "$dst" 2>/dev/null || cp -a "$src" "$dst"
}

ensure_tree() {
  if [[ ! -f $APP_TREE/.voov-provenance ]]; then
    "$ROOT/scripts/prepare.sh" "$@"
  fi
}

# stage_common <root>: launcher plus the version marker it reports on upgrade.
stage_common() {
  local dest=$1
  install -Dm755 "$ROOT/overlay/voov-meeting.sh" "$dest/opt/voov-meeting/bin/voov-meeting"
  printf '%s\n' "$PKG_VERSION" > "$dest/opt/voov-meeting/VERSION"
}