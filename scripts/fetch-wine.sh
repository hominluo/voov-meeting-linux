#!/usr/bin/env bash
# Fetch the portable Wine build bundled with the AppImage and Flatpak.
# The .deb, .rpm and Arch packages use the distribution's Wine instead.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WINE_TREE=$TREE/wine
ARCHIVE=$VENDOR_DIR/$WINE_TARBALL

if [[ -x $WINE_TREE/bin/wine && -f $WINE_TREE/.version \
      && $(cat "$WINE_TREE/.version") == "$WINE_VERSION" ]]; then
  info "Wine $WINE_VERSION already staged at $WINE_TREE"
  exit 0
fi

mkdir -p "$VENDOR_DIR"
if [[ ! -f $ARCHIVE ]]; then
  info "downloading Wine $WINE_VERSION"
  curl -fL --retry 3 -o "$ARCHIVE.part" "$WINE_URL"
  mv "$ARCHIVE.part" "$ARCHIVE"
fi

info "verifying $ARCHIVE"
echo "$WINE_SHA256  $ARCHIVE" | sha256sum -c --quiet -

info "unpacking Wine"
rm -rf "$WINE_TREE.tmp"
mkdir -p "$WINE_TREE.tmp"
tar -xJf "$ARCHIVE" -C "$WINE_TREE.tmp" --strip-components=1

# Keep lib/wine/i386-windows: a win64 prefix still runs 32-bit PE, and wineboot
# fails without it (c0000135). Drop the 32-bit *unix* modules so Wine uses its
# WoW64 mode: the 32-bit wine-preloader needs set_thread_area, which Flatpak's
# seccomp filter kills (SIGSYS). Also drop build-time files.
rm -rf "$WINE_TREE.tmp/lib/wine/i386-unix" \
       "$WINE_TREE.tmp/include" \
       "$WINE_TREE.tmp/share/man"
printf '%s\n' "$WINE_VERSION" > "$WINE_TREE.tmp/.version"

rm -rf "$WINE_TREE"
mv "$WINE_TREE.tmp" "$WINE_TREE"

info "Wine $WINE_VERSION staged at $WINE_TREE"
du -sh "$WINE_TREE"
