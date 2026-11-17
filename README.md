# voov-meeting-linux

An unofficial **native Linux build of VooV Meeting** — Tencent's international
video-conferencing client — distributed as `.deb`, `.rpm`, Flatpak, AppImage
and Snap, with package-manager channels for Debian/Ubuntu (APT), Arch (AUR),
Fedora (COPR), openSUSE (OBS), Nix, and Flathub. **No Wine.**

Tencent ships VooV only for Windows and macOS. Its official Linux client is
the China-only *Tencent Meeting*. This project takes that official Linux
client, applies a small set of binary patches that switch its product identity,
deployment and endpoint tables to the VooV side, and packages it with native
Linux desktop integration.

> **Status: 3.26.10.401 (1) — experimental.**
> The patched client starts natively, connects to VooV's server fleet, and
> **VooV login works end-to-end** through the in-app WeChat QR flow and the
> phone-number form. Joining meetings, camera, microphone and screen sharing
> are not verified yet. See [Roadmap](#roadmap).

![VooV Meeting on Linux — login screen](docs/screenshot.png)

## How it works

- The application payload is Tencent's official Linux client
  `TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb`
  (197,268,516 bytes, SHA-256 `70f37b02…6eacaf`), verified before use.
- The patcher (`scripts/patch-linux-build.py`, idempotent, asserts original
  bytes) re-identifies the client as VooV. The full analysis is in
  [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md); in short:
  1. **`libwemeet_platform.so`** — `default_settings()` is hooked (code cave
     at `0x1706400`) so the two overseas flags in the settings object are
     always set: `+0x420` makes `InitSDK` select the VooV signaling
     endpoints, `+0x4c8` is the field `IsVooVVersion()` reads.
  2. **`libwemeet_app_sdk.so`** — the build-time endpoint table entries
     `conn.wemeet.tencent.com` / `quic.conn.wemeet.qq.com` become
     `conn.voovmeeting.com` / `quic.voovmeeting.com` (the bootstrap host
     comes from a static `{length, pointer}` table, not from a flag).
  3. **Channel** `0300000000` → `1410000197` in three libraries, so VooV's
     backend sees a VooV client.
  4. **Branding** — `腾讯会议` → `VooV Meeting` in the UI resource packs
     (window title included); the resource md5 constants are updated.
  5. **WeChat login** — the QR-login pages load from `voovmeeting.com`
     instead of the China deployment, so the callback completes a VooV login.
  6. **Product identity** — `TM_Product_App` → `TM_Product_VooV`, so a
     VooV-linked WeChat account is not treated as a foreign account.
  7. **Deployment identity** — publish channel `TencentInside` → `Overseas`
     and CGI gateway `work.medialab.qq.com` → `api.voovmeeting.com`; this is
     what makes `POST /v2/account/login/auth-code` return `code: 0`.
  8. **Login page logo** — the four login bitmaps are replaced with the VooV
     artwork from the genuine VooV build.
- The patched client connects to `conn.voovmeeting.com` — verified with an
  `LD_PRELOAD` `getaddrinfo`/`connect` tracer (`scripts/netlog.c`).
- Everything else — the bundled Qt runtime, codecs, plugins — is Tencent's
  own, unmodified.
- The client writes its data to the standard XDG directories and never into
  its install tree, so the package stays read-only under `/opt`.

For the complete engineering record — the static analysis, every patch, the
login debugging and the packaging details — see
[docs/HOW-WE-BUILT-IT.md](docs/HOW-WE-BUILT-IT.md).

## Install

Every channel ships the same patched Tencent Meeting tree. The GitHub release
is always current; the store channels below reuse the release `.deb`, so the
payload is identical everywhere.

| Channel | Status |
| ------- | ------ |
| APT (Debian, Ubuntu) | live |
| Nix flake | live |
| AUR (`voov-meeting-bin`) | package ready, awaiting maintainer key |
| Fedora COPR | spec ready, awaiting upload |
| openSUSE OBS | spec ready, awaiting upload |
| Flathub | manifest ready, awaiting submission |
| Snap Store | snap built, awaiting upload |
| `.deb` / `.rpm` / AppImage / Flatpak bundle | live |

### Arch Linux (AUR)

```bash
yay -S voov-meeting-bin
```

Or build it from source:

```bash
git clone https://aur.archlinux.org/voov-meeting-bin.git
cd voov-meeting-bin && makepkg -si
```

### Debian / Ubuntu (APT)

```bash
echo "deb [trusted=yes] https://github.com/hominluo/voov-meeting-linux/releases/latest/download/ ./" \
  | sudo tee /etc/apt/sources.list.d/voov-meeting.list
sudo apt update
sudo apt install voov-meeting
```

The repository is flat: `Packages` and the `.deb` are release assets, so
`apt update` follows the newest release.

### Fedora (COPR)

```bash
sudo dnf copr enable hominluo/voov-meeting
sudo dnf install voov-meeting
```

### openSUSE (OBS)

```bash
sudo zypper addrepo https://download.opensuse.org/repositories/home:/hominluo/openSUSE_Tumbleweed/home:hominluo.repo
sudo zypper install voov-meeting
```

### Flatpak (Flathub)

```bash
flatpak install flathub io.github.hominluo.voov_meeting_linux
flatpak run io.github.hominluo.voov_meeting_linux
```

Until the Flathub listing is live, install the bundle from the release:

```bash
flatpak install --user ./VooV-Meeting-3.26.10.401-1-x86_64.flatpak
flatpak run io.github.hominluo.voov_meeting_linux
```

The bundle needs the Freedesktop runtime (`org.freedesktop.Platform//25.08`);
Flatpak downloads it from Flathub on first install.

### Snap

```bash
sudo snap install voov-meeting
```

The snap uses classic confinement and installs the same `/opt` tree.

### NixOS / Nix

Flakes must be enabled (`experimental-features = nix-command flakes` in
`nix.conf`; on NixOS `nix.settings.experimental-features`).

```bash
nix profile install github:hominluo/voov-meeting-linux
```

### Direct downloads

All release builds are attached to
[GitHub Releases](https://github.com/hominluo/voov-meeting-linux/releases).

```bash
# Debian / Ubuntu
sudo apt install ./voov-meeting_3.26.10.401-1_amd64.deb

# Fedora / RHEL / openSUSE
sudo dnf install ./voov-meeting-3.26.10.401-1.x86_64.rpm

# Any distribution
chmod +x VooV-Meeting-3.26.10.401-1-x86_64.AppImage
./VooV-Meeting-3.26.10.401-1-x86_64.AppImage

# Snap (without the store)
sudo snap install --classic --dangerous ./voov-meeting_3.26.10.401_amd64.snap
```

The AppImage needs FUSE 2, or run it with `--appimage-extract-and-run`.

There is also an Arch PKGBUILD in `packaging/arch` (`makepkg -si`) that builds
the same `.deb` payload locally.

### First start

The client starts directly — there is no prefix setup or first-run copy. It
keeps its state in `~/.config`, `~/.cache`, `~/.local/share` and
`~/.local/state`.

On Wayland sessions the client runs through XWayland, matching the official
launcher's own behavior.

## Requirements

- x86_64 Linux with glibc, X11 or XWayland.
- Standard desktop libraries: NSS, X11, PulseAudio, libgcrypt, D-Bus, systemd
  (the `.deb`/`.rpm`/Arch packages declare these; the AppImage and Flatpak
  are self-contained or use the Freedesktop runtime).
- A working audio server (PipeWire or PulseAudio) for meetings.

## What is not supported (yet)

- Joining a meeting and the media path (camera, microphone, screen sharing)
  are **unverified**; login itself is verified end-to-end.
- The update and telemetry endpoints still point at Tencent Meeting's China
  servers (`report.meeting.tencent.com`, `updatecdn.meeting.qq.com`) —
  cosmetic, not the meeting channel.
- No native Wayland: the window is an XWayland client.

A note on phone login: the dial-code picker contains all 213 regions and is
searchable. It opens filtered by the current code (`+86`), so clear that entry
and type another code or region name to reach other countries.

## Build from source

Requirements: `bash`, `curl`, `tar`, `xz`, `ar`, `python3`, and for the RPM
build Docker (`rpmbuild` runs inside a Fedora container). Building any format
first runs `scripts/prepare.sh`, which downloads and verifies the official
`.deb` (~197 MB), extracts the tree and applies the patches.

```bash
git clone https://github.com/hominluo/voov-meeting-linux
cd voov-meeting-linux

# 1. Download + verify the official .deb, extract, patch (build/tree)
./scripts/prepare.sh

# 2. Build one or all formats into dist/
./scripts/build-deb.sh
./scripts/build-rpm.sh
./scripts/build-appimage.sh
./scripts/build-flatpak.sh
```

Each build script stages the same patched tree (hard links where possible)
and can be run independently. `prepare.sh` is safe to re-run.

## Versioning

Releases follow the **Tencent Meeting for Linux base version** the client is
built from, with our own rebuild counter in parentheses:

- `3.26.10.401 (1)` — first native build of the 3.26.10.401 base
- `3.26.10.401 (2)` — our next rebuild of the same base
- `3.27.x.x (1)` — new upstream base, counter resets

Git tags and package versions use `3.26.10.401-1` because package managers do
not allow spaces or parentheses. See [RELEASING.md](RELEASING.md).

## Roadmap

- [x] Native client (no Wine) connecting to VooV's signaling fleet
- [x] VooV account login end-to-end (in-app WeChat QR, phone number)
- [x] VooV branding: window title, UI strings, icons, login page logo
- [ ] Verify joining a meeting, camera, microphone, screen sharing
- [ ] Patch the remaining China-only update/report endpoints
- [ ] arm64 build (Tencent ships an official arm64 Linux client)

## Legal

The scripts and packaging in this repository are MIT licensed (see
[LICENSE](LICENSE)). The bundled application is proprietary Tencent software
and is **not** covered by the MIT license; its patched libraries, resource
packs and logo bitmaps are redistributed in patched form — see [NOTICE](NOTICE).

This is an unofficial community project, not affiliated with or supported by
Tencent. VooV Meeting and Tencent Meeting are trademarks of Tencent.