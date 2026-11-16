#!/usr/bin/env bash
# Shared configuration and helpers for the VooV Meeting build scripts.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$ROOT/build}
DIST_DIR=${DIST_DIR:-$ROOT/dist}
TREE=$BUILD_DIR/tree

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

# Linux package our build is derived from (the newest Tencent Meeting Linux
# release at the time of writing; VooV has no Linux client of its own).
UPSTREAM_VERSION=3.26.10.401
UPSTREAM_DEB=TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb
UPSTREAM_SHA256=70f37b029209c0ef91be9813eebf6650c6cb9a00f7c718490158773e2fe6acaf

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }

# cp -al when possible: the app tree is ~672 MB and gets staged several times.
hardlink_copy() {
  local src=$1 dst=$2
  rm -rf "$dst"
  cp -al "$src" "$dst" 2>/dev/null || cp -a "$src" "$dst"
}

ensure_tree() {
  if [[ ! -x $TREE/opt/voov-meeting/bin/wemeetapp ]]; then
    "$ROOT/scripts/prepare.sh" "$@"
  fi
}
