#!/usr/bin/env bash
# Build a Flatpak bundle (single-file .flatpak) with flatpak build-* tools.
# flatpak-builder is not required. The client ships its own Qt; the Chromium
# sandbox of the embedded browser is disabled because it cannot run inside
# the Flatpak sandbox.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ensure_tree "$@"

APP_ID_FLATPAK=io.github.hominluo.voov_meeting_linux
RUNTIME=org.freedesktop.Platform
SDK=org.freedesktop.Sdk
BRANCH=25.08
BUILD=$BUILD_DIR/flatpak
REPO=$BUILD_DIR/flatpak-repo
OUT=$DIST_DIR/VooV-Meeting-${PKG_VERSION}-x86_64.flatpak

info "initialising flatpak build dir"
rm -rf "$BUILD" "$REPO"
flatpak build-init "$BUILD" "$APP_ID_FLATPAK" "$SDK" "$RUNTIME" "$BRANCH"

APPDIR=$BUILD/files
mkdir -p "$APPDIR/bin" "$APPDIR/opt/voov-meeting" \
  "$APPDIR/share/applications" \
  "$APPDIR/share/icons/hicolor/256x256/apps" "$APPDIR/share/metainfo"

info "copying application tree"
hardlink_copy "$APP_TREE" "$APPDIR/opt/voov-meeting/app"
stage_common "$APPDIR"

cat > "$APPDIR/bin/voov-meeting" <<'EOF'
#!/bin/bash
export QTWEBENGINE_DISABLE_SANDBOX=1
exec /app/opt/voov-meeting/bin/voov-meeting "$@"
EOF
chmod 755 "$APPDIR/bin/voov-meeting"

sed -e 's|@EXEC@|voov-meeting|' \
    -e "s|^Icon=.*|Icon=$APP_ID_FLATPAK|" \
    "$ROOT/packaging/common/voov-meeting.desktop.in" \
  > "$APPDIR/share/applications/$APP_ID_FLATPAK.desktop"
for size in 16 32 64 128 256 512; do
  icon=$ROOT/packaging/common/icons/voov-$size.png
  [[ -f $icon ]] || continue
  install -Dm644 "$icon" \
    "$APPDIR/share/icons/hicolor/${size}x${size}/apps/$APP_ID_FLATPAK.png"
done
install -Dm644 "$ROOT/packaging/common/icons/voov.svg" \
  "$APPDIR/share/icons/hicolor/scalable/apps/$APP_ID_FLATPAK.svg"
sed -e "s|@APP_ID@|$APP_ID_FLATPAK|g" \
    -e "s|@RELEASE_NAME@|$RELEASE_NAME|g" \
    -e "s|@VERSION@|$TM_VERSION|g" \
    -e "s|@RELEASE_DATE@|$(date -u +%F)|g" \
    "$ROOT/packaging/flatpak/metainfo.xml.in" > "$APPDIR/share/metainfo/$APP_ID_FLATPAK.metainfo.xml"

info "finishing flatpak"
flatpak build-finish "$BUILD" \
  --command=voov-meeting \
  --share=network \
  --share=ipc \
  --socket=x11 \
  --socket=pulseaudio \
  --device=dri \
  --device=all \
  --filesystem=home \
  --talk-name=org.freedesktop.Notifications \
  --own-name=com.tencent.wemeet

mkdir -p "$REPO" "$DIST_DIR"
flatpak build-export --arch=x86_64 "$REPO" "$BUILD" stable
rm -f "$OUT"
flatpak build-bundle --arch=x86_64 \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
  "$REPO" "$OUT" "$APP_ID_FLATPAK" stable

info "wrote $OUT ($(du -h "$OUT" | cut -f1))"
