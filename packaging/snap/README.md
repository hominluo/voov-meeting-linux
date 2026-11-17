# Snap package

`snapcraft.yaml` builds a **classic-confinement** snap from the published
release `.deb` and produces `voov-meeting_<version>_amd64.snap`. It is the
same application payload as the `.deb`, `.rpm`, AppImage and Flatpak.

## Build

The official Snapcraft image for the `core22` base works on any distro with
Docker or Podman (no snapd needed). From the repository root:

```bash
docker run --rm -v "$PWD/packaging/snap:/project" ghcr.io/canonical/snapcraft:8_core22
```

The image runs `snapcraft pack` in destructive mode with `/project` as the
project directory. The first build downloads the 197 MB `.deb` from the GitHub
release; the source and unpacked trees are cached in `packaging/snap/parts/`
for later builds.

With Snapcraft installed natively (Ubuntu, or the `snapcraft` snap):

```bash
cd packaging/snap
snapcraft pack --destructive-mode
```

The artifact is `packaging/snap/voov-meeting_3.26.10.401_amd64.snap`.
`packaging/snap/.gitignore` keeps the build trees and the artifact out of git.

## Install, test, upload

```bash
sudo snap install --classic --dangerous ./voov-meeting_3.26.10.401_amd64.snap

snapcraft upload --release=stable ./voov-meeting_3.26.10.401_amd64.snap
```

The name `voov-meeting` is available in the store; register it once with
`snapcraft register voov-meeting`. Classic confinement requires a one-time
store approval before the first upload: request it in the Snapcraft forum's
*store-requests* category with the snap name and a short explanation (the
client needs the host's devices, network and the bundled Qt). Later uploads of
the same snap do not need another request.

## How it is put together

- **Part**: the `dump` plugin over the release `.deb`
  (`source-type: deb`, SHA-256 pinned). Running the `.deb`'s maintainer
  scripts is unnecessary: they only refresh the desktop and icon caches.
- **Command**: `opt/voov-meeting/bin/voov-meeting`, the release launcher,
  used as-is. It sets `QT_QPA_PLATFORM=xcb`/`XDG_SESSION_TYPE=x11` on Wayland
  sessions, and `LD_LIBRARY_PATH`/`QT_PLUGIN_PATH` for the bundled Qt.
  The `.deb`'s `/usr/bin/voov-meeting` is an absolute symlink into the host's
  `/opt`, so the snap does not use it; `override-build` rewrites it as a
  relative link so it resolves inside the snap too.
- **Desktop entry**: `apps.voov-meeting.desktop` points at the `.deb`'s
  `usr/share/applications/voov-meeting.desktop`. Snapcraft rewrites
  `Exec=/opt/voov-meeting/bin/voov-meeting %u` to `Exec=voov-meeting %u`,
  rewrites `Icon=` to `${SNAP}/meta/gui/icon.png`, and installs the result as
  `meta/gui/voov-meeting.desktop`. Snapd exports **only** `meta/gui` desktop
  files (not `usr/share/applications`) and rewrites the command to
  `/snap/bin/voov-meeting`, which is the wrapper of the classic snap. `Name`,
  `Name[zh_CN]`, `StartupWMClass=wemeetapp`, the MIME handlers and the
  categories are preserved.
- **Icon**: `icon.png` (256×256, a copy of
  `packaging/common/icons/voov-256.png`) is installed as `meta/gui/icon.png`
  and used by the store and the desktop entry.

## Checks after a build

```bash
unsquashfs -l voov-meeting_3.26.10.401_amd64.snap |
  grep -E 'meta/(snap.yaml|gui/)|opt/voov-meeting/(bin/voov-meeting|app/bin/wemeetapp)'

unsquashfs -cat voov-meeting_3.26.10.401_amd64.snap meta/snap.yaml
unsquashfs -cat voov-meeting_3.26.10.401_amd64.snap meta/gui/voov-meeting.desktop
```

After installing, the copy exported by snapd should carry the absolute
wrapper path:

```bash
grep -E '^(Exec|Icon|StartupWMClass)=' \
  /var/lib/snapd/desktop/applications/voov-meeting_voov-meeting.desktop
# Exec=/snap/bin/voov-meeting %u
```

## Risks and notes

- **Desktop `Exec` is rewritten twice**: snapcraft turns the absolute path
  into the app name, snapd turns the app name into `/snap/bin/voov-meeting`.
  This relies on the app being named `voov-meeting` (same as the snap). If the
  app is ever renamed, the `Exec` line must be renamed with it. A future
  snapd change to desktop-file sanitising would affect all classic snaps, not
  just this one.
- **Host libraries**: a classic snap uses the host's glibc and desktop
  libraries (NSS, X11, PulseAudio, libgcrypt, D-Bus, systemd — the `.deb`'s
  `Depends`), as the other formats do; the bundled Qt is used.
- **Classic linter warnings**: snapcraft notes that the bundled ELFs keep
  their original interpreter/rpath (`/lib64/ld-linux-x86-64.so.2`) rather
  than `/snap/core22/current/...`. This is intentional: the payload is
  Tencent's prebuilt client and, like the `.deb`, it loads host libraries;
  mixing the base's glibc with host libraries would be the riskier
  combination. The warnings do not block `pack` or upload.
- **Desktop validation**: `desktop-file-validate` warns about
  `Icon=${SNAP}/meta/gui/icon.png` in the packed file; snapd expands
  `${SNAP}` to `/snap/voov-meeting/current` when it exports the entry.
- **Wayland**: the launcher forces XWayland, as in every other package here.
  No plugs are needed under classic confinement.
- **QtWebEngine sandbox**: the client's embedded browser uses user
  namespaces (the `.deb` ships no setuid `chrome-sandbox`). On hosts that
  block unprivileged user namespaces, start it with
  `QTWEBENGINE_DISABLE_SANDBOX=1`.
- **Release bump**: update `version`, the `source` URL and
  `source-checksum` (SHA-256 of the new `.deb`), and `icon.png` if the
  artwork changed.
