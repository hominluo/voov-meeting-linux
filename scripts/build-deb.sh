#!/usr/bin/env bash
# Build the Debian package without dpkg-deb (works on Arch and other distros).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ensure_tree "$@"

STAGE=$BUILD_DIR/deb
ROOT_DIR=$STAGE/root
DEB=$DIST_DIR/${APP_ID}_${PKG_VERSION}_amd64.deb

info "staging Debian tree"
rm -rf "$STAGE"
mkdir -p "$ROOT_DIR/DEBIAN" "$ROOT_DIR/opt" \
  "$ROOT_DIR/usr/bin" \
  "$ROOT_DIR/usr/share/applications" \
  "$ROOT_DIR/usr/share/doc/$APP_ID"

hardlink_copy "$TREE/opt/voov-meeting" "$ROOT_DIR/opt/voov-meeting"

for size in 32 64 128 256 512; do
  icon=$ROOT/packaging/common/icons/voov-$size.png
  [[ -f $icon ]] || continue
  install -Dm644 "$icon" "$ROOT_DIR/usr/share/icons/hicolor/${size}x${size}/apps/voov-meeting.png"
done
install -Dm644 "$ROOT/packaging/common/icons/voov-256.png" "$ROOT_DIR/usr/share/pixmaps/voov-meeting.png"

sed 's|@EXEC@|/opt/voov-meeting/wemeetapp.sh|' \
  "$ROOT/packaging/common/voov-meeting.desktop.in" > "$ROOT_DIR/usr/share/applications/voov-meeting.desktop"

ln -s /opt/voov-meeting/wemeetapp.sh "$ROOT_DIR/usr/bin/voov-meeting"

installed_size=$(du -sk "$ROOT_DIR/opt" | cut -f1)
sed -e "s|@VERSION@|${PKG_VERSION}|" \
    -e "s|@INSTALLED_SIZE@|$installed_size|" \
    -e "s|@RELEASE_NAME@|$RELEASE_NAME|g" \
    -e "s|@APP_VERSION@|$APP_VERSION|g" \
    -e "s|@UPSTREAM_VERSION@|$UPSTREAM_VERSION|g" \
    "$ROOT/packaging/deb/control.in" > "$ROOT_DIR/DEBIAN/control"

install -m755 "$ROOT/packaging/deb/postinst" "$ROOT_DIR/DEBIAN/postinst"
install -m755 "$ROOT/packaging/deb/prerm" "$ROOT_DIR/DEBIAN/prerm"

info "writing md5sums"
(cd "$ROOT_DIR" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' \
  | LC_ALL=C sort -z | xargs -0 md5sum > DEBIAN/md5sums)
chmod 644 "$ROOT_DIR/DEBIAN/md5sums"

printf 'VooV Meeting %s (unofficial Linux build)\nVooV Meeting release: %s\nBase package: Tencent Meeting %s\nhttps://github.com/hominluo/voov-meeting-linux\n' "$PKG_VERSION" "$RELEASE_NAME" "$UPSTREAM_VERSION" \
  > "$ROOT_DIR/usr/share/doc/$APP_ID/copyright"

info "compressing (this takes a few minutes)"
mkdir -p "$DIST_DIR"
printf '2.0\n' > "$STAGE/debian-binary"
tar -C "$ROOT_DIR" --exclude=./DEBIAN --owner=0 --group=0 --numeric-owner -cf - . \
  | xz -T0 -6 -c > "$STAGE/data.tar.xz"
tar -C "$ROOT_DIR/DEBIAN" --owner=0 --group=0 --numeric-owner -cf - . \
  | xz -T0 -6 -c > "$STAGE/control.tar.xz"

rm -f "$DEB"
(cd "$STAGE" && ar rc "$DEB" debian-binary control.tar.xz data.tar.xz)

info "wrote $DEB ($(du -h "$DEB" | cut -f1))"
