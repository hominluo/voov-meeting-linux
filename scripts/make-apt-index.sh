#!/usr/bin/env bash
# Build the Packages index for the flat APT repository that is published as
# release assets. The repository is consumed as
#
#   deb [trusted=yes] https://github.com/hominluo/voov-meeting-linux/releases/latest/download/ ./
#
# so the index and the .deb live in the same (flat) directory.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DEB=$DIST_DIR/voov-meeting_${PKG_VERSION}_amd64.deb
OUT=${1:-$DIST_DIR/Packages}

[[ -f $DEB ]] || die "missing $DEB"

size=$(stat -c %s "$DEB")
sha=$(sha256sum "$DEB" | cut -d' ' -f1)

# Keep the control stanza in sync with packaging/deb/control.in.
cat > "$OUT" <<EOF
Package: voov-meeting
Version: $PKG_VERSION
Architecture: amd64
Maintainer: Homin Luo <homin.ro@gmail.com>
Installed-Size: 687292
Depends: libnss3, libx11-6, libxrandr2, desktop-file-utils, libpulse0, libgcrypt20, libdbus-1-3, libsystemd0, libudev1
Recommends: xdg-utils, libnotify-bin
Suggests: pipewire
Section: net
Priority: optional
Homepage: https://github.com/hominluo/voov-meeting-linux
Filename: $(basename "$DEB")
Size: $size
SHA256: $sha
Description: Unofficial native VooV Meeting client
 Tencent ships VooV only for Windows and macOS. This package republishes
 Tencent's official Linux client with small binary patches that switch it
 to VooV's regional settings and endpoints. It runs natively, without Wine.
EOF

gzip -9 -nc "$OUT" > "$OUT.gz"
xz -9 -c "$OUT" > "$OUT.xz"

cat > "$DIST_DIR/Release" <<EOF
Origin: voov-meeting
Label: voov-meeting
Suite: stable
Codename: stable
Version: 1.0
Architectures: amd64
Components: main
Description: Unofficial native VooV Meeting client
Date: $(date -Ru)
SHA256:
 $(sha256sum "$OUT" | cut -d' ' -f1) $(stat -c %s "$OUT") Packages
EOF

info "wrote $OUT ($(du -h "$OUT" | cut -f1)), $OUT.gz, $OUT.xz and Release"
