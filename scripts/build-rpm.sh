#!/usr/bin/env bash
# Build an RPM inside a Fedora container (rpmbuild is not required on the host).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ensure_tree "$@"

STAGE=$BUILD_DIR/rpm-root
SPEC=$BUILD_DIR/voov-meeting.spec

info "staging RPM root"
rm -rf "$STAGE"
mkdir -p "$STAGE/opt/voov-meeting" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/doc/voov-meeting"
hardlink_copy "$APP_TREE" "$STAGE/opt/voov-meeting/app"
stage_common "$STAGE"
ln -s /opt/voov-meeting/bin/voov-meeting "$STAGE/usr/bin/voov-meeting"
for size in 32 64 128 256 512 1024; do
  icon=$ROOT/packaging/common/icons/voov-$size.png
  [[ -f $icon ]] || continue
  install -Dm644 "$icon" "$STAGE/usr/share/icons/hicolor/${size}x${size}/apps/voov-meeting.png"
done
install -Dm644 "$ROOT/packaging/common/icons/voov-256.png" "$STAGE/usr/share/pixmaps/voov-meeting.png"
sed 's|@EXEC@|/opt/voov-meeting/bin/voov-meeting|' \
  "$ROOT/packaging/common/voov-meeting.desktop.in" > "$STAGE/usr/share/applications/voov-meeting.desktop"
printf 'VooV Meeting %s (unofficial Linux build)\nVooV Meeting for Windows: %s (running under Wine)\nhttps://github.com/hominluo/voov-meeting-linux\n' \
  "$PKG_VERSION" "$APP_VERSION" > "$STAGE/usr/share/doc/voov-meeting/copyright"

info "writing spec"
mkdir -p "$BUILD_DIR"
sed -e "s|@VERSION@|$VOO_V_VERSION|g" \
    -e "s|@RELEASE@|$BUILD_NUMBER|g" \
    "$ROOT/packaging/rpm/voov-meeting.spec.in" > "$SPEC"

mkdir -p "$DIST_DIR"
info "building in fedora:latest (downloads rpm-build if needed)"
docker run --rm \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$ROOT:/src:ro" \
  -v "$DIST_DIR:/dist" \
  fedora:latest bash -euo pipefail -c '
    if ! command -v rpmbuild >/dev/null; then
      dnf -y install rpm-build >/dev/null
    fi
    QA_RPATHS=0xffff rpmbuild -bb --define "_topdir /tmp/rpmbuild" /src/build/voov-meeting.spec
    cp /tmp/rpmbuild/RPMS/x86_64/*.rpm /dist/
    chown "$HOST_UID:$HOST_GID" /dist/*.rpm
  '

ls -lh "$DIST_DIR"/*.rpm
