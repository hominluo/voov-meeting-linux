# How the native Linux VooV Meeting client was built

This is the full engineering record of how Tencent's official Linux *Tencent
Meeting* build was turned into a native **VooV Meeting** client — no Wine, with
working VooV account login, VooV branding and Linux packages.

The short version: Tencent already compiles the same product for Linux, but
ships it with the China product's identity baked in. Rather than reimplement a
~800 MB C++ client (or run the Windows build under Wine), we changed the
identity — product, deployment, channel, endpoints and branding — inside
Tencent's own binaries, using the genuine VooV macOS build as ground truth.

---

## 1. The problem

VooV Meeting is Tencent's international video-conferencing client. Tencent
publishes it for Windows, macOS, iOS and Android, and publishes **no Linux
package at all**. Its Linux desktop client is *Tencent Meeting*, the China
product: same codebase, different product identity and different servers.

Two approaches were possible:

1. **Repackage the Windows client under Wine.** This works, and was the
   project's first incarnation (the 3.43.0.510 releases), but it is heavy,
   fragile, and drags a full Windows runtime into the desktop.
2. **Re-identify Tencent's own Linux build as VooV.** The Linux client already
   contains the overseas code paths, the VooV endpoints and the same UI
   framework. The difference is configuration and identity, most of it baked
   in at build time.

We chose (2). The result is a native Qt application, with Tencent's own
bundled runtime, that talks to VooV's servers and logs in with a real VooV
account.

## 2. Ground truth: the genuine VooV builds

To know what "VooV" means to the code, we compared the official clients:

| Build | Version | Role |
| --- | --- | --- |
| VooV for Windows | 3.43.0.510 | channel `1410000197`, `wemeet_app_sdk.dll` defaults table |
| VooV for macOS | 3.43.0.510 | channel `1410000198`, `wemeet_app_components` and nxres assets |
| Tencent Meeting for Linux | 3.26.10.401 | the base we patch (channel `0300000000`) |

The macOS bundle was especially useful: it ships the same nxres resource tree
as the Linux build, including the identical 213-country dial-code XML files
and the VooV login-logo bitmaps. The Windows DLL provided the endpoint and
channel constants. Where the clients disagree, the genuine VooV build wins.

## 3. The base build

Everything starts from Tencent's official Linux package, pinned and verified:

```
TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb
197,268,516 bytes
MD5     72e0e0023e1d1e6d4123fba28821aea1
SHA-256 70f37b029209c0ef91be9813eebf6650c6cb9a00f7c718490158773e2fe6acaf
```

`scripts/prepare.sh` checks size, MD5 and SHA-256, extracts `data.tar.xz`,
keeps the `/opt/wemeet` tree, and runs the patcher. The tree ends up in
`build/tree`, and every package is staged from that one tree.

The Linux client is **Qt 5.15 + QtWebEngine** (the Windows/macOS builds are
Qt 6 + CEF). It bundles its own Qt, plugins, codecs and IME support, so the
system needs no Qt at all.

## 4. What had to change

| Concern | Mechanism | Where |
| --- | --- | --- |
| Overseas mode | `default_settings()` hook forcing `+0x420`/`+0x4c8` | `libwemeet_platform.so` |
| Signaling bootstrap | static endpoint table strings | `libwemeet_app_sdk.so` |
| Distribution channel | `0300000000` → `1410000197` | three libraries |
| Product name | `腾讯会议` → `VooV Meeting` (UI resources) | `wemeet.res`, settings pack |
| WeChat QR pages | `meeting.tencent.com` → `voovmeeting.com` | `libwemeet_module_api.so` |
| Product identity | `TM_Product_App` → `TM_Product_VooV` | components + app sdk |
| Deployment identity | `TencentInside` → `Overseas`, CGI host | `libwemeet_app_sdk.so` |
| Login page art | VooV `login_guide_logo` bitmaps | nxres assets |
| Wayland crash | run through XWayland | launcher script |

The next sections explain each one, and how it was verified.

## 5. The patch set

`scripts/patch-linux-build.py <tree>` applies everything in place. It asserts
original bytes and sizes, prefers equal-length or NUL-padded replacements,
uses code caves and relocation updates when a string grows, updates the
resource md5 constants, and is idempotent. Running it twice is a no-op; running
it on a fresh extraction produces exactly the tree that was runtime-tested.

### Patch 1 — force the overseas flags (`libwemeet_platform.so`)

The client decides "am I VooV?" from one boolean:
`wemeetsdk::utils::version_util::IsVooVVersion()` compiles to
`return default_settings()->[0x4c8];`. The signaling bootstrap switches to the
overseas address set only when `settings[+0x420] != 0`, so both bytes are
forced.

`default_settings()` (vaddr `0x231940`) is redirected with a `jmp rel32` to a
36-byte code cave at `0x1706400`, an unused NUL run inside the R+E LOAD
segment. The cave reproduces the original selection logic (static default at
`0x1d0c6b8`, JSON-provided settings at `0x1d0cc48`) and then sets both flags:

```asm
1706400:  lea    0x1d0c6b8(%rip),%rax
1706407:  mov    0x1d0cc48(%rip),%rcx
170640e:  test   %rcx,%rcx
1706411:  cmovne %rcx,%rax
1706415:  movb   $1,0x420(%rax)
170641c:  movb   $1,0x4c8(%rax)
1706423:  ret
```

### Patch 2 — replace the baked-in signaling endpoints (`libwemeet_app_sdk.so`)

The first signaling host does not come from a flag. It is a build-time
`{length, pointer}` table in `.data.rel.ro`. Two entries are replaced in
place; the new strings are shorter and NUL-padded:

| What | File offset | From | To |
| --- | --- | --- | --- |
| conn body | `0x1c5bbc8` | `conn.wemeet.tencent.com` | `conn.voovmeeting.com` |
| quic body | `0x1c5bbe0` | `quic.conn.wemeet.qq.com` | `quic.voovmeeting.com` |
| conn length | table `0x23284d0` | `0x17` | `0x14` |
| quic length | table `0x23284e0` | `0x17` | `0x14` |

After patches 1–2 the process holds a stable TLS connection to
`conn.voovmeeting.com`; this was verified with an `LD_PRELOAD`
`getaddrinfo`/`connect` tracer (`scripts/netlog.c`).

### Patch 3 — channel identity

The download channel is baked in as an 11-byte (string + NUL) constant.
Servers use it to decide which product is calling; the China id made VooV's
auth backend reject VooV-linked accounts. `0300000000` → `1410000197` (same
length) in:

| Library | File offset |
| --- | --- |
| `lib/libwemeet_app_sdk.so` | `0x1c5bce0` |
| `lib/libwemeet.so` | `0x0d6538` |
| `bin/modules/schedule_meeting/libschedule_meeting_module.so` | `0x61d710` |

### Patch 4 — product name in the resource packs

UI strings live in nxui resource packs as `{u32 length, UTF-8 bytes}` entries.
`VooV Meeting` is exactly the 12 UTF-8 bytes of `腾讯会议`, so the replacement
is length-preserving:

| Pack | Occurrences |
| --- | --- |
| `bin/wemeet.res` (window title included) | 7 |
| `bin/modules/settings/module.res` | 3 |

Both packs are md5-checked at load time (the checker lives in
`libwemeet_framework.so`, logging `expect md5:` / `md5 not matched`). The
32-byte hex constants inside the checking libraries are therefore updated to
the new digests: `libwemeet_app_sdk.so` holds md5(`bin/wemeet.res`) and
`bin/modules/settings/libsettings_module.so` holds
md5(`bin/modules/settings/module.res`).

### Patch 5 — WeChat QR-login pages

The WeChat login webview loaded its QR page from the China deployment. After
the phone confirmed the scan, WeChat redirected through the China callback,
which could not match a VooV account — the phone showed `登录失败`. Both login
literals in `lib/libwemeet_module_api.so` were switched to the
`voovmeeting.com` equivalents that the genuine VooV client loads:

| File offset | From | To |
| --- | --- | --- |
| `0x75a127` | `https://meeting.tencent.com/v2/qrcode-login?` | `https://voovmeeting.com/v2/qrcode-login?` |
| `0x75a154` | `https://meeting.tencent.com/v2/qrcode/auth?` | `https://voovmeeting.com/v2/qrcode/auth?` |

Both are NUL-terminated C strings consumed through `std::string(const char*)`,
so the four-bytes-shorter replacements are NUL-padded in place.

### Patch 6 — product identity

The build identified itself as the Tencent Meeting product in two static
`std::string_view` constants (`{length, pointer}`). With `TM_Product_App`, the
in-app login flow treated a VooV-linked WeChat account as a foreign account
and popped the "already bound to a VooV Meeting account" dialog.

`TM_Product_VooV` is one byte longer, so each copy is relocated into a spare
`.rodata` run; the view length/pointer and the `R_X86_64_RELATIVE` relocation
addend are repointed:

| Library | Views (vaddr) | Relocations | Cave |
| --- | --- | --- | --- |
| `lib/libwemeet_app_components.so` | `0xc3d3d8`, `0xc3e3c8` | `0xe3d3e0`, `0xe3e3d0` | `0x98312c` |
| `lib/libwemeet_app_sdk.so` | `0x2328550` | `0x2528558` | `0x1b2e0e0` |

The relocation part matters: the dynamic loader writes `base+addend` over the
data slot at load time, so patching only the file bytes would leave the old
pointer in place.

### Patch 7 — deployment identity (the one that made login work)

Two more China-deployment defaults sit in the same table as the product type:
the publish channel `TencentInside` (sent as `c_app_publish_channel`) and the
CGI gateway `https://work.medialab.qq.com`. The China gateway rewrote every
request as a Tencent Meeting login regardless of `c_product_id`; a WeChat
account already linked to VooV failed with `-20003`.

The genuine VooV builds send `c_app_publish_channel=Overseas` to
`https://api.voovmeeting.com` and complete the same exchange with `code: 0`.
Both replacements are shorter and NUL-padded; the view lengths are updated:

| Library | File offset | From → To | Views |
| --- | --- | --- | --- |
| `lib/libwemeet_app_sdk.so` | `0x1aa4d8c` | `TencentInside` → `Overseas` | `0x24e9e10`, `0x2511bb0`, `0x2511f20`, `0x25176b0`, `0x251d6c0`, `0x2528548` |
| `lib/libwemeet_app_sdk.so` | `0x1c5bbf8` | `https://work.medialab.qq.com` → `https://api.voovmeeting.com` | `0x25284f8` |

View addresses are `.data.rel.ro` vaddrs; each length is the u64 immediately
before the relocated pointer.

### Patch 8 — login page logo

The Linux resource index (`nxres/resources.fb`) lists only the Tencent Meeting
login artwork. The genuine VooV build ships the same bitmap in the same slot
under a `_voov` name. Since the Linux index has no `_voov` entries, the four
plain slots are overwritten with the VooV art:

- `drawable-xhdpi-v4/login_guide_logo.png`
- `drawable-xxhdpi-v4/login_guide_logo.png`
- `drawable-night-xhdpi-v8/login_guide_logo.png`
- `drawable-night-xxhdpi-v8/login_guide_logo.png`

The bitmaps live in `scripts/branding/`, copied from the VooV macOS bundle.
No hash check rejected them; the login window was relaunched and renders the
VooV logo.

### The one non-binary fix: the launcher

On Wayland the client must run through XWayland. Its X11 helper breaks under
the Qt Wayland platform: `QX11Info::display()` returns the `wl_display`, and
the first Xlib call on that path — `XInternAtom` in `x_utils::SetStayOnTop`,
reached from the WeChat-login view — segfaults.

`overlay/voov-meeting.sh` therefore forces, on Wayland sessions:

```bash
export QT_QPA_PLATFORM=xcb
export XDG_SESSION_TYPE=x11
export WEMEET_XWAYLAND=1
unset WAYLAND_DISPLAY
```

This matters on desktops like Omarchy, which preset
`QT_QPA_PLATFORM=wayland;xcb`; just having `xcb` in the list is not enough.
Tencent's own launcher does the same.

## 6. The login debugging story

Getting to `code: 0` took four distinct fixes. Each symptom pointed at a
different layer:

1. **Crash when opening the WeChat view** — the Wayland/X11 helper described
   above. Fixed in the launcher, not in the binary.
2. **Phone showed `登录失败` after confirming the scan** — the QR page and the
   callback lived on the China deployment, which could not match a VooV
   account. Patch 5 moved both to `voovmeeting.com`.
3. **"This WeChat account is already bound to a VooV Meeting account"** — the
   app still identified as `TM_Product_App`. Patch 6 changed the product type
   to `TM_Product_VooV`.
4. **Auth exchange returned `-20003`** — the request still went to the China
   CGI gateway (`work.medialab.qq.com`) with `c_app_publish_channel=
   TencentInside`. Patch 7 moved it to `api.voovmeeting.com` with
   `c_app_publish_channel=Overseas`.

The decisive evidence came from tracing the native HTTP layer under gdb: every
URL built by `GetUrlWithCommonParams*`, the request bodies
(`PrintRequestBody`/`SetBody`) and every response body (`OnResponse`). The
auth exchange is:

```
POST https://api.voovmeeting.com/v2/account/login/auth-code
     ?c_product_id=...&c_app_publish_channel=Overseas
     &c_sdk_id=1410000197&c_instance_id=10
body: {"auth_code":"<uuid>","identity_type":"1","is_change_account":"0"}
```

The successful response:

```json
{"code":0,"message":"success", ...,
 "data":{"userid":"144115224030243521","nick_name":"HominLuo",
         "is_register":true, ...}}
```

`is_register: true` means the login also created/attached the VooV account on
first use. That first login showed a one-time "取消 / 切换账号" prompt; after
the account existed, normal relaunches went straight to the home screen.

Signaling calls (`get-connection-conf`, `query-visitor-ability-config`,
`get-time-zone-info`) also all go to `api.voovmeeting.com` with the patched
build.

## 7. Phone login and the region list

The phone-number form uses the runtime DynamicResource country list. The
investigation was straightforward once the files were located:

- `country_code_4_sms_{en,zh,tc,ja,ko,ms}.xml` arrive from the server into
  `DynamicResource/<hash>/` — 213 countries each.
- They are **byte-identical** to the files in the genuine VooV macOS bundle.
- The region dropdown is a search list: with the picker showing `+86`, it
  lists exactly the dial codes containing "86" (`+86`, `+1868`, `+1869`,
  `+386`, `+686`, `+886`) — not a truncated list.
- Clearing the `+86` text (BackSpace in the picker) shows the full list; typing
  `44` filters to `+44 United Kingdom`, `+1441 Bermuda`, `+244 Angola`.

So overseas phone login needs **no patch**. The README notes the interaction:
clear the prefilled `+86` and search for another code or region.

## 8. Branding

- **Window title and in-app name**: patch 4 replaces `腾讯会议` with
  `VooV Meeting` in the resource packs; the window title is one of those
  strings.
- **Launcher entry**: `packaging/common/voov-meeting.desktop.in` provides
  `Name=VooV Meeting`, `StartupWMClass=wemeetapp`, icon `voov-meeting`, and
  the `wemeet`/`voovmeeting` URL handlers.
- **Icons**: Tencent's VooV icon art, exported at 16, 32, 64, 128, 256, 512
  and 1024 px plus a scalable SVG, installed into
  `hicolor/{size}x{size}/apps/voov-meeting.png` and
  `hicolor/scalable/apps/voov-meeting.svg`.
- **Login page**: patch 8 swaps the Tencent Meeting logo for the VooV logo,
  day and night variants.

## 9. Packaging

All formats are staged from the same patched tree (`build/tree`), with a
single launcher (`overlay/voov-meeting.sh`) and a shared desktop file:

| Format | Build | Notes |
| --- | --- | --- |
| `.deb` | `scripts/build-deb.sh` | no `dpkg-deb` needed: `ar` + `tar` + `xz` |
| `.rpm` | `scripts/build-rpm.sh` | `rpmbuild` inside a `fedora:latest` container |
| AppImage | `scripts/build-appimage.sh` | self-contained; `appimagetool` |
| Flatpak bundle | `scripts/build-flatpak.sh` | Freedesktop 25.08 runtime |
| APT repository | `scripts/make-apt-index.sh` | flat repo; `Packages`/`Release` as release assets |
| AUR | `packaging/aur/voov-meeting-bin` | `-bin` repack of the release `.deb` |
| Fedora COPR | `packaging/fedora/voov-meeting.spec` | the `.deb` is `Source0`, unpacked in `%install` |
| openSUSE OBS | `packaging/opensuse/voov-meeting.spec` | same approach |
| Flathub | `packaging/flathub/` | `extra-data`; payload downloaded at install time |
| Snap | `packaging/snap/snapcraft.yaml` | classic confinement; built in the Snapcraft 8 image |
| Nix | `flake.nix` | wraps the release `.deb`, supplies host libraries |

Practical details that cost time:

- The Flatpak icon validator rejects 1024×1024 app icons (max 512), so the
  Flatpak installs 16–512 and the SVG.
- A redistributable Flatpak cannot carry Tencent's binaries, so the Flathub
  manifest uses an `extra-data` source. `apply_extra` runs at install time
  and unpacks the `.deb` with `python3` (the runtime has no `ar`) and `tar`.
- The RPM `%files` list must name every installed file; the added SVG had to
  be listed explicitly or `rpmbuild` fails with "Installed (but unpackaged)
  file(s) found".
- `rpm` itself is not needed on the host; the build script does the RPM work
  in Docker.
- The `.deb`'s `/usr/bin/voov-meeting` is an absolute symlink into `/opt`;
  the snap replaces it with a relative one, or the link would resolve on the
  host rather than inside the snap.
- The AppImage expects FUSE 2 (or `--appimage-extract-and-run`).
- State lives in the standard XDG directories; `/opt` stays read-only.

Versioning follows the upstream Linux base with our own build counter:
`3.26.10.401 (1)`, tag and package version `3.26.10.401-1`. When a build with
the same version is wrong, the assets of the existing tag are replaced rather
than bumping the counter (see `RELEASING.md`).

## 10. Verification

The claims in this document were checked, not assumed:

- **Patch reproducibility.** A fresh extraction of the official `.deb` was
  patched with `scripts/patch-linux-build.py`. All 13 modified files (nine
  binaries/resource packs and four logo bitmaps) are SHA-256 identical to the
  tree used for the runtime tests.
- **Idempotency.** Running the patcher a second time changes nothing and
  reports the already-patched state.
- **Runtime.** The patched client launches natively under XWayland, reaches
  `conn.voovmeeting.com`, completes WeChat login with `code: 0`, and shows the
  home screen. The phone form lists all 213 regions and the login logo is the
  VooV artwork.
- **Packages.** The `.deb`, `.rpm`, AppImage and Flatpak bundle were rebuilt
  from the same tree; the APT index was resolved by a real `apt update` in a
  `debian:stable-slim` container, the AUR package was built with `makepkg`,
  the Fedora and openSUSE specs were built with `rpmbuild`, the Flathub
  manifest with `flatpak-builder`, the Snap with Snapcraft 8, and the Nix
  flake with `nix build`. Contents were spot-checked (launcher, 16 px icon,
  SVG) and the release `SHA256SUMS` regenerated.

Patched digests for the two most important libraries:

| File | Size | Original SHA-256 | Patched SHA-256 |
| --- | --- | --- | --- |
| `libwemeet_platform.so` | 28,364,080 B | `664b932a0839a3ad8dc19dd0627f12635e21bf1253f763b18b27e8264376e196` | `2308afe831bb7ddfd3a700da4ac289a3550a0d7d0259ca603ef7e4d1c5e94f84` |
| `libwemeet_app_sdk.so` | 37,031,336 B | `554da86e823eeefde3b4c4ff5fd47d2c60ea7c676900692e08608a641f9bdd70` | `39b46e4ff429e7003b54fc3d11b628d4fdfe2b748fd1e45d990cb62c0884177c` |

## 11. Repository map

```
scripts/prepare.sh              verify + extract the official .deb, apply patches
scripts/patch-linux-build.py    the 8 VooV patches (idempotent)
scripts/branding/               VooV login-logo bitmaps (from the VooV build)
overlay/voov-meeting.sh         launcher (XWayland handling, bundled Qt env)
packaging/common/icons/         icon art (16–1024 px, SVG)
packaging/common/voov-meeting.desktop.in
scripts/build-{deb,rpm,appimage,flatpak}.sh
scripts/make-apt-index.sh        flat APT repository index
overlay/voov-meeting.sh         launcher (XWayland handling, bundled Qt env)
packaging/common/icons/         icon art (16–1024 px, SVG)
packaging/common/voov-meeting.desktop.in
packaging/arch/PKGBUILD         builds from the release .deb
packaging/aur/voov-meeting-bin  AUR (-bin) package
packaging/fedora/               COPR spec + instructions
packaging/opensuse/             OBS spec + instructions
packaging/flathub/              Flathub manifest (extra-data) + support files
packaging/snap/                 snapcraft.yaml + build instructions
packaging/nix/, flake.nix       Nix package
docs/REVERSE-ENGINEERING.md     static-analysis report + patch details
docs/PUBLISHING.md              per-channel publishing procedure
docs/releases/                  release notes
```

Build from source:

```bash
./scripts/prepare.sh          # downloads, verifies, extracts, patches
./scripts/build-deb.sh        # or any other build-*.sh
```

## 12. Known limitations

- **Meetings and media are unverified.** Login, home screen, signaling and
  phone/WeChat auth are tested; joining a meeting, camera, microphone and
  screen sharing are the next validation step.
- **Some China endpoints remain**: `report.meeting.tencent.com`,
  `updatecdn.meeting.qq.com` and the CDN/short-connection hosts are
  update/report surfaces, not the meeting channel.
- **XWayland only.** The window is an X11 client; native Wayland is not
  implemented.
- **Proprietary payload.** The application is Tencent's, redistributed patched;
  only the scripts and packaging are MIT licensed (see `NOTICE`).
