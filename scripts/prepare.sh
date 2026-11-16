#!/usr/bin/env bash
# Verify and unpack the official VooV Meeting for Windows installer, producing
# the Wine application tree in build/tree/app.
#
# Usage: scripts/prepare.sh [/path/to/VooVMeeting_..._x86_64.publish.exe]
#
# The installer is looked up (in order) in the argument, $VOO_EXE_PATH,
# vendor/, and ~/Downloads/; if it is not found it is downloaded from Tencent.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ -z ${1:-} && -z ${VOO_EXE_PATH:-} ]]; then
  for candidate in "$VENDOR_DIR/$VOO_EXE" "$HOME/Downloads/$VOO_EXE"; do
    [[ -f $candidate ]] && { set -- "$candidate"; break; }
  done
fi
candidate=${1:-${VOO_EXE_PATH:-}}

verify() {
  local file=$1 size md5 sha
  size=$(stat -c %s "$file")
  [[ $size == "$VOO_EXE_SIZE" ]] || die "unexpected size: $size (expected $VOO_EXE_SIZE)"
  md5=$(md5sum "$file" | cut -d' ' -f1)
  [[ $md5 == "$VOO_EXE_MD5" ]] || die "unexpected MD5: $md5 (expected $VOO_EXE_MD5)"
  sha=$(sha256sum "$file" | cut -d' ' -f1)
  [[ $sha == "$VOO_EXE_SHA256" ]] || die "unexpected SHA-256: $sha (expected $VOO_EXE_SHA256)"
}

if [[ -n $candidate ]]; then
  [[ -f $candidate ]] || die "installer not found: $candidate"
else
  mkdir -p "$VENDOR_DIR"
  candidate=$VENDOR_DIR/$VOO_EXE
  info "downloading $VOO_EXE"
  curl -fL --retry 3 -o "$candidate.part" "$VOO_EXE_URL"
  mv "$candidate.part" "$candidate"
fi

info "verifying $candidate"
verify "$candidate"

# --- 7-Zip ---------------------------------------------------------------
sevenz=$(command -v 7zz || command -v 7z || true)
if [[ -z $sevenz ]]; then
  sevenz=$BUILD_DIR/tools/7zz
  if [[ ! -x $sevenz ]]; then
    info "downloading 7-Zip"
    mkdir -p "$BUILD_DIR/tools"
    curl -fL --retry 3 -o "$BUILD_DIR/tools/7z.tar.xz" "$SEVENZ_URL"
    echo "$SEVENZ_SHA256  $BUILD_DIR/tools/7z.tar.xz" | sha256sum -c --quiet -
    tar -xJf "$BUILD_DIR/tools/7z.tar.xz" -C "$BUILD_DIR/tools" 7zz
  fi
fi

# --- unpack --------------------------------------------------------------
info "unpacking the installer"
rm -rf "$BUILD_DIR/extract" "$APP_TREE"
mkdir -p "$BUILD_DIR/extract"
"$sevenz" x -y -bso0 -bsp0 -o"$BUILD_DIR/extract" "$candidate"

payload=$BUILD_DIR/extract/'$_22_'
[[ -f $payload/wemeet.dll ]] || die "unexpected installer payload (no 3.43.0.510 tree)"
[[ -f $BUILD_DIR/extract/VooVMeetingApp.exe ]] || die "unexpected installer payload (no launcher)"
[[ -f $BUILD_DIR/extract/voovmeetingapp_new.exe ]] || die "unexpected installer payload (no app executable)"

info "staging the application tree"
mkdir -p "$APP_TREE"
mv "$payload" "$APP_TREE/$VOO_V_VERSION"
install -m644 "$BUILD_DIR/extract/VooVMeetingApp.exe" "$APP_TREE/VooVMeetingApp.exe"
install -m644 "$BUILD_DIR/extract/voovmeetingapp_new.exe" "$APP_TREE/voovmeetingapp_new.exe"

# The installer only creates these two root executables. VooV launches the
# other names from the same binaries, and its updater looks for them, so the
# package provides them.
cp -p "$APP_TREE/VooVMeetingApp.exe" "$APP_TREE/voovmeetinglauncher.exe"
cp -p "$APP_TREE/voovmeetingapp_new.exe" "$APP_TREE/voovmeetingapp.exe"
cp -p "$APP_TREE/voovmeetingapp_new.exe" "$APP_TREE/WeMeetWebview.exe"

# Required because Wine has no SLWGA.dll (see src/slwga/README.md).
install -m644 "$ROOT/src/slwga/SLWGA.dll" "$APP_TREE/$VOO_V_VERSION/SLWGA.dll"

# Drop the installer scaffolding; keep a small provenance file.
rm -rf "$BUILD_DIR/extract"
{
  printf 'app=%s\n' "$VOO_V_VERSION"
  printf 'installer=%s\n' "$VOO_EXE"
  printf 'installer-sha256=%s\n' "$VOO_EXE_SHA256"
} > "$APP_TREE/.voov-provenance"

# The launcher installs this tree into the user's Wine prefix on first run and
# re-installs it when the manifest changes.
manifest=$(cd "$APP_TREE" && find . -type f ! -name .voov-manifest -printf '%P %s\n' \
  | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
printf '%s\n' "$manifest" > "$APP_TREE/.voov-manifest"

info "application tree ready at $APP_TREE (manifest $manifest)"
du -sh "$APP_TREE"
