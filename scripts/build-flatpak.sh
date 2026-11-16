#!/usr/bin/env bash
# Build a Flatpak bundle (single-file .flatpak) with flatpak build-* tools.
# flatpak-builder is not required.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ensure_tree "$@"

APP_ID_FLATPAK=com.voovmeeting.VooVMeeting
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
mkdir -p "$APPDIR/bin" "$APPDIR/opt" "$APPDIR/share/applications" \
  "$APPDIR/share/icons/hicolor/256x256/apps" "$APPDIR/share/metainfo"

info "copying application tree"
hardlink_copy "$TREE/opt/voov-meeting" "$APPDIR/opt/voov-meeting"

cat > "$APPDIR/bin/voov-meeting" <<'EOF'
#!/bin/bash
exec /app/opt/voov-meeting/wemeetapp.sh "$@"
EOF
chmod 755 "$APPDIR/bin/voov-meeting"

sed -e 's|@EXEC@|voov-meeting|' \
    -e "s|^Icon=.*|Icon=$APP_ID_FLATPAK|" \
    "$ROOT/packaging/common/voov-meeting.desktop.in" \
  > "$APPDIR/share/applications/$APP_ID_FLATPAK.desktop"
install -m644 "$ROOT/packaging/common/icons/voov-256.png" \
  "$APPDIR/share/icons/hicolor/256x256/apps/$APP_ID_FLATPAK.png"
sed -e "s|@APP_ID@|$APP_ID_FLATPAK|g" \
    -e "s|@RELEASE_NAME@|$RELEASE_NAME|g" \
    "$ROOT/packaging/flatpak/metainfo.xml.in" > "$APPDIR/share/metainfo/$APP_ID_FLATPAK.metainfo.xml"

info "finishing flatpak"
flatpak build-finish "$BUILD" \
  --command=voov-meeting \
  --share=network \
  --share=ipc \
  --socket=x11 \
  --socket=pulseaudio \
  --device=dri \
  --filesystem=home \
  --talk-name=org.freedesktop.Notifications \
  --own-name=com.tencent.wemeet \
  --env=QT_QPA_PLATFORM=xcb

mkdir -p "$REPO" "$DIST_DIR"
flatpak build-export --arch=x86_64 "$REPO" "$BUILD" stable
rm -f "$OUT"
flatpak build-bundle --arch=x86_64 \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
  "$REPO" "$OUT" "$APP_ID_FLATPAK" stable

info "wrote $OUT ($(du -h "$OUT" | cut -f1))"
