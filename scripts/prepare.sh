#!/usr/bin/env bash
# Download + verify the official Tencent Meeting for Linux .deb, extract the
# application tree and apply the VooV patches, producing the tree in
# build/tree (the contents the packages install under /opt/voov-meeting/app).
#
# Usage: scripts/prepare.sh [/path/to/TencentMeeting_..._.deb]
#
# The .deb is looked up (in order) in the argument, $TM_DEB_PATH, vendor/ and
# ~/Downloads/; if it is not found it is downloaded from Tencent's CDN.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ -z ${1:-} && -z ${TM_DEB_PATH:-} ]]; then
  for candidate in "$VENDOR_DIR/$TM_DEB" "$HOME/Downloads/$TM_DEB"; do
    [[ -f $candidate ]] && { set -- "$candidate"; break; }
  done
fi
candidate=${1:-${TM_DEB_PATH:-}}

verify() {
  local file=$1 size md5 sha
  size=$(stat -c %s "$file")
  [[ $size == "$TM_DEB_SIZE" ]] || die "unexpected size: $size (expected $TM_DEB_SIZE)"
  md5=$(md5sum "$file" | cut -d' ' -f1)
  [[ $md5 == "$TM_DEB_MD5" ]] || die "unexpected MD5: $md5 (expected $TM_DEB_MD5)"
  sha=$(sha256sum "$file" | cut -d' ' -f1)
  [[ $sha == "$TM_DEB_SHA256" ]] || die "unexpected SHA-256: $sha (expected $TM_DEB_SHA256)"
}

if [[ -n $candidate ]]; then
  [[ -f $candidate ]] || die ".deb not found: $candidate"
else
  mkdir -p "$VENDOR_DIR"
  candidate=$VENDOR_DIR/$TM_DEB
  info "downloading $TM_DEB"
  curl -fL --retry 3 -o "$candidate.part" "$TM_DEB_URL"
  mv "$candidate.part" "$candidate"
fi

info "verifying $candidate"
verify "$candidate"

info "extracting the application tree"
rm -rf "$BUILD_DIR/extract" "$TREE"
mkdir -p "$BUILD_DIR/extract"
ar p "$candidate" data.tar.xz | tar -xJf - -C "$BUILD_DIR/extract"
[[ -d $BUILD_DIR/extract/opt/wemeet ]] || die "unexpected .deb payload (no opt/wemeet)"

mv "$BUILD_DIR/extract/opt/wemeet" "$TREE"
[[ -x $TREE/bin/wemeetapp ]] || die "unexpected tree layout (no bin/wemeetapp)"
rm -rf "$BUILD_DIR/extract"

info "applying the VooV patches"
python3 "$ROOT/scripts/patch-linux-build.py" "$TREE"

{
  printf 'app=%s\n' "$APP_VERSION"
  printf 'source-deb=%s\n' "$TM_DEB"
  printf 'source-deb-sha256=%s\n' "$TM_DEB_SHA256"
} > "$TREE/.voov-provenance"

info "patched application tree ready at $TREE"
du -sh "$TREE"