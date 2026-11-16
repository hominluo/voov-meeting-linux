#!/usr/bin/env bash
# Verify, extract and patch the upstream Tencent Meeting .deb package.
#
# Usage: scripts/prepare.sh [/path/to/TencentMeeting_....deb]
#
# The package is looked up (in order) in the argument, $UPSTREAM_DEB_PATH,
# vendor/, and ~/Downloads/.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

candidate=${1:-${UPSTREAM_DEB_PATH:-}}
if [[ -z $candidate ]]; then
  if [[ -f $ROOT/vendor/$UPSTREAM_DEB ]]; then
    candidate=$ROOT/vendor/$UPSTREAM_DEB
  elif [[ -f $HOME/Downloads/$UPSTREAM_DEB ]]; then
    candidate=$HOME/Downloads/$UPSTREAM_DEB
  fi
fi
[[ -n $candidate && -f $candidate ]] || die "upstream .deb not found; download it from https://meeting.tencent.com/download-center.html and pass the path"

info "verifying $candidate"
actual=$(sha256sum "$candidate" | cut -d' ' -f1)
[[ $actual == "$UPSTREAM_SHA256" ]] || die "unexpected SHA-256: $actual (expected $UPSTREAM_SHA256)"

info "extracting"
rm -rf "$BUILD_DIR/extract" "$TREE" "$BUILD_DIR/app"
mkdir -p "$BUILD_DIR/extract" "$TREE"
(cd "$BUILD_DIR/extract" && ar x "$candidate")
tar -xf "$BUILD_DIR/extract/data.tar.xz" -C "$TREE"
[[ -d $TREE/opt/wemeet ]] || die "unexpected package layout"

info "applying patches"
mv "$TREE/opt/wemeet" "$TREE/opt/voov-meeting"
python3 "$ROOT/scripts/apply-patches.py" "$TREE/opt/voov-meeting"

info "patched tree ready at $TREE/opt/voov-meeting"
