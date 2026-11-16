# voov-meeting-linux

An unofficial **native Linux build of VooV Meeting** — Tencent's international
video-conferencing client — packaged as `.deb`, `.rpm`, Flatpak, AppImage and
Arch package. **No Wine.**

Tencent ships VooV only for Windows and macOS. Its official Linux client is
the China-only *Tencent Meeting*. This project takes that official Linux
client, applies two small binary patches that switch its regional settings
and endpoint tables to the VooV side, and packages it with native Linux
desktop integration.

> **Status: 3.26.10.401 (1) — experimental.**
> The patched client starts natively and establishes its signaling connection
> to `conn.voovmeeting.com`, VooV's server fleet. Signing in with a VooV
> account, joining meetings, camera, microphone and screen sharing have not
> been verified yet. See [Roadmap](#roadmap).

![VooV Meeting (patched Tencent Meeting) running on Linux](docs/screenshot.png)

## How it works

- The application payload is Tencent's official Linux client
  `TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb`
  (197,268,516 bytes, SHA-256 `70f37b02…6eacaf`), verified before use.
- Two patches are applied to two libraries; the full analysis is in
  [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md) and the patcher
  is `scripts/patch-linux-build.py` (idempotent, asserts original bytes):
  1. **`libwemeet_platform.so`** — `default_settings()` is hooked (code cave
     at `0x1706400`) so the two overseas flags in the settings object are
     always set: `+0x420` makes `InitSDK` select the VooV signaling endpoints,
     `+0x4c8` is the field `IsVooVVersion()` reads.
  2. **`libwemeet_app_sdk.so`** — the build-time endpoint table entries
     `conn.wemeet.tencent.com` / `quic.conn.wemeet.qq.com` become
     `conn.voovmeeting.com` / `quic.voovmeeting.com` (the bootstrap host comes
     from a static `{length, pointer}` table, not from a flag).
- The patched client then connects to `conn.voovmeeting.com` — verified with
  an `LD_PRELOAD` `getaddrinfo`/`connect` tracer (`scripts/netlog.c`).
- Everything else — the bundled Qt runtime, codecs, plugins — is Tencent's
  own, unmodified.
- The client writes its data to the standard XDG directories and never into
  its install tree, so the package stays read-only under `/opt`.

## Install

All release builds are attached to
[GitHub Releases](https://github.com/hominluo/voov-meeting-linux/releases).
Pick the format for your distribution.

### Debian / Ubuntu (`.deb`)

```bash
sudo apt install ./voov-meeting_3.26.10.401-1_amd64.deb
voov-meeting
```

### Fedora / RHEL / openSUSE (`.rpm`)

```bash
sudo dnf install ./voov-meeting-3.26.10.401-1.x86_64.rpm
voov-meeting
```

### Any distribution (AppImage)

```bash
chmod +x VooV-Meeting-3.26.10.401-1-x86_64.AppImage
./VooV-Meeting-3.26.10.401-1-x86_64.AppImage
```

The AppImage needs FUSE 2, or run it with `--appimage-extract-and-run`.

### Flatpak

```bash
flatpak install --user ./VooV-Meeting-3.26.10.401-1-x86_64.flatpak
flatpak run com.voovmeeting.VooVMeeting
```

The bundle needs the Freedesktop runtime (`org.freedesktop.Platform//25.08`);
Flatpak downloads it from Flathub on first install.

### Arch Linux

```bash
cd packaging/arch
makepkg -si
```

The PKGBUILD downloads the release `.deb` and installs its contents under
`/opt/voov-meeting`.

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

- Signing in with a VooV account and joining meetings are **unverified** —
  the build still reports version 3.26.10.401 and channel `0300000000`, and
  whether VooV's servers accept that identity is the main open question.
- The window title and parts of the UI still show 腾讯会议 (the China
  product's branding).
- The update and telemetry endpoints still point at Tencent Meeting's China
  servers (`report.meeting.tencent.com`, `updatecdn.meeting.qq.com`) —
  cosmetic, not the meeting channel.
- No native Wayland: the window is an XWayland client.

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
- [ ] Verify VooV account login end-to-end
- [ ] Verify joining a meeting, camera, microphone, screen sharing
- [ ] VooV branding: window title, UI strings, icons
- [ ] Patch the remaining China-only endpoints (update/report)
- [ ] arm64 build (Tencent ships an official arm64 Linux client)

## Legal

The scripts and packaging in this repository are MIT licensed (see
[LICENSE](LICENSE)). The bundled application is proprietary Tencent software
and is **not** covered by the MIT license; two of its libraries are
redistributed in patched form — see [NOTICE](NOTICE).

This is an unofficial community project, not affiliated with or supported by
Tencent. VooV Meeting and Tencent Meeting are trademarks of Tencent.