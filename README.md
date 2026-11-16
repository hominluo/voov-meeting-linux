# voov-meeting-linux

An unofficial **Linux build of VooV Meeting** — Tencent's international
video-conferencing client — packaged as `.deb`, `.rpm`, Flatpak and AppImage.

Tencent ships a Linux client only for the China-only *Tencent Meeting*
product. This project takes Tencent's official Linux package, patches its
signaling endpoints to the international VooV infrastructure, and repackages it
with native Linux integration.

> **Status: 3.43.0.510 (1) — experimental.**
> The client starts on X11/XWayland, resolves `conn.voovmeeting.com` for
> signaling, and reaches the login screen in the `.deb`, AppImage, Flatpak and
> RPM builds. The login flow itself and in-meeting features have not yet been
> verified with a VooV account, and the UI still carries Tencent Meeting
> branding. See [Roadmap](#roadmap).

![Login screen](docs/screenshot.png)

## Install

All release builds are attached to
[GitHub Releases](https://github.com/hominluo/voov-meeting-linux/releases).
Pick the format for your distribution.

### Debian / Ubuntu (`.deb`)

```bash
sudo apt install ./voov-meeting_3.43.0.510-1_amd64.deb
voov-meeting
```

### Fedora / RHEL / openSUSE (`.rpm`)

```bash
sudo dnf install ./voov-meeting-3.43.0.510-1.x86_64.rpm
voov-meeting
```

### Any distribution (AppImage)

```bash
chmod +x VooV-Meeting-3.43.0.510-1-x86_64.AppImage
./VooV-Meeting-3.43.0.510-1-x86_64.AppImage
```

The AppImage needs FUSE 2, or run it with `--appimage-extract-and-run`.
It uses XWayland under Wayland sessions.

### Flatpak

```bash
flatpak install --user ./VooV-Meeting-3.43.0.510-1-x86_64.flatpak
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

## What is patched

The application tree is taken unmodified from Tencent's official package
except for these byte-level patches (all verified against SHA-256 checksums in
[`patches/patches.json`](patches/patches.json)):

| File | Change |
| ---- | ------ |
| `lib/libwemeet_app_sdk.so` | Signaling host `conn.wemeet.tencent.com` → `conn.voovmeeting.com` |
| `lib/libwemeet_app_sdk.so` | QUIC host `quic.conn.wemeet.qq.com` → `quic.voovmeeting.com` |
| `lib/libwemeet_app_sdk.so` | Lengths in the adjacent `string_view` table adjusted to match |
| `wemeetapp.sh` | Launcher no longer forces `LC_ALL=zh_CN.UTF-8` / `TZ=Asia/Shanghai`, and execs the bundled binary by absolute path |

Everything else — the UI, codecs, plugins, translations — is Tencent's
3.26.10.401 Linux build.

### Why not Wine, or a from-scratch client?

The Windows VooV client installs and runs under Wine, but camera, screen
sharing, audio devices and Wayland integration are all second-class. Tencent's
native Linux build already solves those problems; only the product/regional
configuration differs. Patching the shared code path is the smallest change
that produces a native client.

## Build from source

Requirements:

- `bash`, `python3`, `ar`, `tar`, `xz`, `binutils`
- ~4 GB free disk space (the app tree is 672 MB and is staged several times)
- For packaging: `flatpak` + Freedesktop SDK for Flatpak, Docker for RPM,
  `appimagetool` (downloaded automatically) for AppImage

```bash
git clone https://github.com/hominluo/voov-meeting-linux
cd voov-meeting-linux

# 1. Download Tencent's official Linux package and put it in vendor/:
#    https://meeting.tencent.com/download-center.html
#    (file: TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb)
mkdir -p vendor
cp ~/Downloads/TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb vendor/

# 2. Extract + patch into build/tree
./scripts/prepare.sh

# 3. Build one or all formats into dist/
./scripts/build-deb.sh
./scripts/build-appimage.sh
./scripts/build-flatpak.sh
./scripts/build-rpm.sh
```

`scripts/prepare.sh` verifies the upstream `.deb` SHA-256 before doing
anything, and `scripts/apply-patches.py` refuses to patch a file it does not
recognize. Both are safe to re-run.

## Versioning

Releases follow the **VooV Meeting product version**, with our own rebuild
counter in parentheses:

- `3.43.0.510 (1)` — first build of VooV 3.43.0.510
- `3.43.0.510 (2)` — our next rebuild of the same product version
- `3.44.0.520 (1)` — new VooV version, counter resets

Git tags and package versions use `3.43.0.510-1` because package managers do
not allow spaces or parentheses. See [RELEASING.md](RELEASING.md).

## Roadmap

- [x] Native client on Wayland/XWayland
- [x] VooV signaling endpoint
- [ ] Verify VooV account login end-to-end
- [ ] Switch the remaining product endpoints (`report.*`, API host) to VooV
- [ ] VooV branding in the login screen and window title
- [ ] Replace Tencent Meeting assets/icons where VooV has different ones
- [ ] Verify camera, microphone, screen share and meeting join

## Legal

The scripts, patches and packaging in this repository are MIT licensed
(see [LICENSE](LICENSE)). The bundled application is proprietary Tencent
software and is **not** covered by the MIT license — see [NOTICE](NOTICE).

This is an unofficial community project, not affiliated with or supported by
Tencent. VooV Meeting and Tencent Meeting are trademarks of Tencent.
