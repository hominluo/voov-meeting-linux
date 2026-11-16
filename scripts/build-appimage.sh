#!/usr/bin/env bash
# Build a portable AppImage. Unlike the distro packages, the AppImage bundles
# Wine so it runs on systems without one installed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ensure_tree "$@"
ensure_bundled_wine

TOOL_DIR=$BUILD_DIR/tools
TOOL=$TOOL_DIR/appimagetool-x86_64.AppImage
if [[ ! -x $TOOL ]]; then
  info "downloading appimagetool"
  mkdir -p "$TOOL_DIR"
  curl -fL --retry 3 -o "$TOOL" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi

APPDIR=$BUILD_DIR/AppDir
info "staging AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/opt/voov-meeting/lib"
hardlink_copy "$APP_TREE" "$APPDIR/opt/voov-meeting/app"
hardlink_copy "$TREE/wine" "$APPDIR/opt/voov-meeting/lib/wine"
stage_common "$APPDIR"

install -m755 "$ROOT/packaging/appimage/AppRun" "$APPDIR/AppRun"
sed 's|@EXEC@|voov-meeting|' "$ROOT/packaging/common/voov-meeting.desktop.in" \
  > "$APPDIR/voov-meeting.desktop"
install -m644 "$ROOT/packaging/common/icons/voov-256.png" "$APPDIR/voov-meeting.png"
install -m644 "$ROOT/packaging/common/icons/voov-256.png" "$APPDIR/.DirIcon"

mkdir -p "$DIST_DIR"
OUT=$DIST_DIR/VooV-Meeting-${PKG_VERSION}-x86_64.AppImage
rm -f "$OUT"
info "running appimagetool"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 \
  "$TOOL" --no-appstream --comp zstd "$APPDIR" "$OUT"

info "wrote $OUT ($(du -h "$OUT" | cut -f1))"
