# VooV Meeting 3.43.0.510 — reverse-engineering report

Findings from static analysis of the official Windows and macOS clients, plus the
official Linux Tencent Meeting build, done to decide how a native Linux VooV
client can exist without Wine.

Everything below was read from the shipped binaries and Tencent's own download
API. No code was executed from the Windows or macOS builds.

## Artifacts analysed

| Build | File | Size | Digest |
| --- | --- | --- | --- |
| Windows | `VooVMeeting_1410000197_3.43.0.510_x86_64.publish.exe` | 281,696,512 B | MD5 `a8d7f83c02853ae055ae5f9cfdcae781`, SHA-256 `92649c45…a330fc` |
| macOS | `VooVMeeting_1410000198_3.43.0.510.publish.x86_64.dmg` | 245,494,002 B | MD5 `09ec308a02c61e0ede83ffac486e5cea` |
| Linux (China) | `TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb` | 197,268,516 B | SHA-256 `70f37b02…6eacaf` |

Build metadata, Windows: branch `release/overseas_VooV3.43`, commit
`f8f32d71371eb72206e6aa5e7c60fcea9c1e503e`, build id `510`.
Build metadata, Linux: branch `release/release_3.26.10_linux`, build id `401`.

The Windows installer is NSIS-3 Unicode and unpacks to 5,744 files / 800 MB.
The macOS DMG is HFS+ with a 479 MB bundle.

## The client is not Electron

There is no `app.asar`, no Node runtime, no Electron anywhere in either build.
The desktop client is:

- **Qt 6 Widgets** — `Qt6Core/Gui/Widgets/OpenGL/OpenGLWidgets/Svg/Xml/StateMachine/Core5Compat`
  (macOS additionally links `QtDBus` and `QtPrintSupport`), plus Tencent's own
  `qt_ui_framework`.
- **CEF** for embedded web content — `chrome_100_percent.pak`, `chrome_200_percent.pak`,
  `icudtl.dat`, `snapshot_blob.bin`, `v8_context_snapshot.bin`, `libEGL`/`libGLESv2`,
  and on Windows `WeMeetWebCore.dll`, `WeMeetWebBroker.dll`, `webview_ppapi_plugin.dll`.

"Rebuild the Electron project" therefore has no literal meaning: there is no
JavaScript application to rebuild. Any native rewrite is a new client.

## Architecture

The product is a modular plugin host, not a monolith.

| Layer | Windows | macOS |
| --- | --- | --- |
| Entry | `voovmeetingapp.exe` | `VooV Meeting.app` |
| SDK/loader | `wemeet_app_sdk.dll` | `wemeet_app_sdk.framework` |
| Core platform | `wemeet_platform.dll` (32,048 exports) | `wemeet_platform.framework` |
| Base | `wemeet_base.dll` (4,248 exports) | `wemeet_base.framework` |
| App/components | `wemeet_app_components.dll` | `wemeet_app_components.framework` |
| Legacy shell | `DuiLib.dll` | — |
| UI framework | `qt_ui_framework.dll`, `nxui/` | `qt_ui_framework.framework`, NxUI |
| Modules | `modules/<group>/*.dll` | `ModulesDependency.framework/…` |

`wemeet_app_sdk` exposes the whole boot sequence in five symbols:

```
GetAppModuleRuntime()            -> IModuleRuntime*
InitModuleRuntimeLoader()
InitUiModuleLoader(path, cb, cb)
InitLLVM()                       -> crash handler / symbolisation
Activate / Deactivate            -> ATL DLL entry points
```

Module groups, identical on both platforms:

`home`, `inmeeting`, `cooperation`, `built_in_apps`, `meetlog`,
`meetlog_entrance`, `relationship`, `miscx`.

Individual modules are separate binaries with a `manifest.json` that declares
route schemes (`wemeet://page/...`), UI contributions, activation events, and
`exclude_build` rules. Those rules name `Linux` explicitly, which is direct
evidence that the same module tree is compiled for a Linux target.

### UI layer

NxUI is an Android-derived declarative UI system:

- Resources use Android qualifiers — `res/drawable-mdpi-v4`,
  `drawable-night-xhdpi-v8`, `values-*`.
- Layouts ship as **FlatBuffers** (`nxui/*/nxres/resources.fb`).
- `nxui/*/resources.wres` are **ZIP archives** (verified: `PK\x03\x04`).

So the desktop UI is shared with mobile, and its layout data is machine-readable.

## Protocol stack

| Concern | Component | Evidence |
| --- | --- | --- |
| RPC framework | TRPC | `trpc::wemeet_pb` namespaces in symbols |
| Message schema | protobuf, `wemeet_pb` | 98 embedded `.proto` descriptors |
| Transport | QUIC + HTTPS | `tquic.dll` → `TnetQuicRequest`, `SetAlpn`, `SendQuicMessage` |
| Chat/storage | ImSDK, WCDB | `imsdk.dll`, `WCDB.dll` |
| Media relay | "pere" fleet | `pere.tencent.com`, `pere-fwd.media.meeting.tencent.com` |
| Media proxy | hybrid relay | `relay.hybridproxy.meeting.tencent.com:7778` |
| Screen share | xcast | `xcast.dll`, `config.xcast.qq.com:12312` |
| Codecs | FFmpeg fork | `avcodec_wm-61`, `avformat_wm-61`, `swscale_wm-8`, `libmuxer`, `libr264`, `libr265decoder` |
| AI | XNN / TNN | `xnn_core.dll`, `TNN.dll` |
| Beauty/AR | XMagic + YouTu | `XmagicDll.dll` (74 MB), `YTFaceTracker`, `YT3DAvatar` |
| GPU effects | parvati_engine | C API: `parvati_engine_run`, `set_tracked_faces` |
| Crypto | TencentSM | `libTencentSM.dll` (SM2/3/4) |

The embedded protobuf descriptors are the important part: filenames such as
`wemeet_pb/wemeet_meeting_subgroup/join_subgroup/join_subgroup.proto` and
`wemeet_pb/meeting_control/screen_share_queue/screen_share_queue.proto` mean the
**signalling schema is recoverable** from the binaries.

The media plane is not. It is a proprietary relay protocol over UDP with
Tencent's own congestion control, codec wrappers and key exchange; nothing in
either build exposes it as a usable library boundary.

## Region switching: one codebase, two products

The same binaries serve Tencent Meeting (China) and VooV (international). The
switch is runtime state, not a separate code path:

- `wemeetsdk::utils::version_util::IsVooVVersion()` compiles to
  `return default_settings()->[0x4c8];` — a single boolean field.
- `WEMEET_CUSTOM_CONFIG::GetProductType()` / `IsProductRooms()` /
  `IsProductController()` expose the product identity.
- Default settings serialise as JSON with keys `env_id` (string) and `test_env`
  (bool): `wemeetsdk::utils::settings::GetDefaultSettingsByJson()` and
  `SetDefaultSettingsByJson(JsonValue)`.
- The overseas utility layer is compiled in on **both** platforms, including
  Linux: `wemeet_common::utils::overseas::{GetOverseasWebUrl,
  GetGoogleLoginWebUrl, GetAppleLoginWebUrl, OverseasNetworkDetect,
  LawfulPCNavigate, ReportPolicyUpdate}`.

Endpoints differ by region:

| Purpose | VooV (international) | Tencent Meeting (China) |
| --- | --- | --- |
| CGI API | `api.voovmeeting.com` | `api.corp.wemeet.tencent.com` |
| Signalling | `conn.voovmeeting.com` | `conn.corp.wemeet.tencent.com` |
| QUIC signalling | `quic.voovmeeting.com` | `quic.corp.wemeet.tencent.com` |
| SSO | `sso.voovmeeting.com` | — |
| Reporting | `report.voovmeeting.com` | `report.meeting.tencent.com` |
| Proxy | `dt.proxy.voovmeeting.com` | — |

The distribution channel, however, is **baked in at build time**:

- VooV Windows `wemeet_app_sdk.dll` contains `1410000197`.
- VooV macOS contains `1410000198`.
- Linux `libwemeet_app_sdk.so` contains `0300000000` and no VooV channel.

## Linux: Tencent already ships this product natively

Tencent publishes an official Linux Tencent Meeting client. The download API
behind their site confirms it:

```
GET https://meeting.tencent.com/web-service/query-download-info?q=[{"package-type":"app","channel":"0300000000","platform":"linux","arch":"x86_64","decorators":["deb"]}]
-> version 3.26.10.401, 197,268,516 B
```

x86_64 and arm64 both exist. The Linux build is **Qt 5.15 + QtWebEngine**, i.e.
an older branch than the Qt 6 + CEF desktop builds, packaged as
`/opt/wemeet` with bundled Qt, Wayland and IME support
(`plugins/platforms/libqwayland-*.so`, `platforminputcontexts`).

It runs natively on this machine with no Wine: a `wemeetapp` window appears and
the process establishes TLS to `162.14.19.56:443`, one of the addresses of
`conn.wemeet.tencent.com`.

VooV itself publishes **no** Linux package. VooV's own download configuration
enumerates exactly `mac`, `windows`, `ios`, `android`, `outlook`. Querying the
download API for VooV channels (`1410000197`, `1410000198`) on `linux` returns
`null` for every arch and decorator.

## What this means for a native Linux client

1. **A from-scratch reimplementation of the client is not a viable product.**
   The desktop build is ~800 MB of compiled C++ with a proprietary media plane.
   Recovering the signalling schemas is realistic; replacing the relay media
   engine is not.

2. **The Linux client exists but is the China product.** It contains the
   overseas code (`is_overseas`, `kConnOverseaStaticAddresses`,
   `conn.voovmeeting.com`, the whole overseas utility layer) but identifies as
   channel `0300000000`. Whether VooV's servers would accept it after forcing
   `is_overseas` is unknown, and it would be a patch to a proprietary binary
   pinned to an old branch.

3. **VooV's web client is the only officially supported way to hold a real VooV
   meeting on Linux.** VooV documents SSO login followed by "Join Now" in the
   browser (beta). That runs in Chromium, which is the same engine CEF embeds in
   the official desktop client.

## Recommended direction

Ship a native Linux desktop client that hosts VooV's own web experience inside a
native shell, with the platform integration the browser cannot do alone:

- PipeWire / xdg-desktop-portal screen sharing
- tray, notifications, `voovmeeting://` deep links
- `.deb`, `.rpm`, AppImage and Flatpak packaging

This is native Linux, needs no Wine, and uses Tencent's real service. The
limitation is honest: the meeting experience is VooV's web client, so it inherits
whatever the beta supports, and the home/schedule surfaces are those of the web
build rather than the desktop build.

The alternative — re-identifying Tencent's Linux binary as VooV — was chosen and
shipped; the next section documents the mechanism and the verification evidence.
It remains a binary patch against a proprietary client that lags the desktop
releases.

## Patch spike: re-identifying the Linux build as VooV

Method: static analysis of the two Linux libraries only, followed by runtime
verification with an `LD_PRELOAD` tracer (`scripts/netlog.c`, built with
`gcc -O2 -fPIC -shared -o netlog.so netlog.c -ldl -lpthread`; set
`LD_PRELOAD`/`WEMEET_NETLOG`) that logs every `getaddrinfo` and `connect`. Each
run used a fresh XDG directory set and the tree's own bundled Qt:

```
LD_LIBRARY_PATH=$PWD/lib QT_PLUGIN_PATH=$PWD/plugins QT_QPA_PLATFORM=xcb \
  ./bin/wemeetapp --target=main
```

Steady-state network behaviour per configuration:

| Configuration | Signalling host |
| --- | --- |
| unpatched (baseline) | `conn.wemeet.tencent.com` (162.14.19.56) |
| settings flag `+0x4c8` forced only | `conn.wemeet.tencent.com` — unchanged |
| flag hook + string patch (both flags) | `conn.voovmeeting.com` (162.14.17.87 / 162.14.20.170), stable for the life of the process |

### Patch 1 — force the overseas flags (`libwemeet_platform.so`)

- `wemeetsdk::utils::version_util::IsVooVVersion()` compiles to
  `return default_settings()->[0x4c8];` — one boolean field.
- `InitSDK` (replacement site `0x12a8928`) swaps the conn address for the VooV
  set (`kConnOverseaStaticAddresses`, referenced at `0xed00e5`) **only if**
  `settings[+0x420] != 0`. Forcing `+0x4c8` alone does not flip the conn host,
  so both bytes are forced.
- The returned object is selected by
  `wemeetsdk::utils::settings::default_settings()` (vaddr `0x231940`; `.text` is
  identity-mapped, file offset == vaddr): the static default at
  `.bss 0x1d0c6b8`, or the JSON-provided object at `0x1d0cc48` once
  `SetDefaultSettingsByJson` has run.

`default_settings()` (22-byte body + 10-byte nop pad) is redirected with a
`jmp rel32` to a 36-byte code cave at `0x1706400` — an unreferenced NUL run
inside `.rodata`, which sits in the first, `R E` LOAD segment (verified: no
RIP-relative code refs and no RELA addends into `[0x1706400, 0x17067d0)`). The
cave reproduces the original selection logic and then sets both flags:

```asm
1706400:  lea    0x1d0c6b8(%rip),%rax     # static default settings object
1706407:  mov    0x1d0cc48(%rip),%rcx     # JSON-provided settings pointer
170640e:  test   %rcx,%rcx
1706411:  cmovne %rcx,%rax
1706415:  movb   $1,0x420(%rax)           # overseas endpoint selector (InitSDK)
170641c:  movb   $1,0x4c8(%rax)           # IsVooVVersion()
1706423:  ret
```

### Patch 2 — replace the baked-in conn strings (`libwemeet_app_sdk.so`)

The bootstrap conn host does not come from any flag: it is a build-time
static-initialised string table in `.data.rel.ro` — `{length, pointer}` pairs
into `.rodata` (`conn.wemeet.tencent.com` @ vaddr `0x25284d0`). Two entries are
patched in place; the replacements are shorter and NUL-padded, so no ELF layout
changes are needed:

| What | File offset | From | To |
| --- | --- | --- | --- |
| conn string body | `0x1c5bbc8` | `conn.wemeet.tencent.com` (0x17) | `conn.voovmeeting.com` (0x14) |
| quic string body | `0x1c5bbe0` | `quic.conn.wemeet.qq.com` | `quic.voovmeeting.com` |
| conn length field | `0x23284d0` (vaddr `0x25284d0`) | `0x17` | `0x14` |
| quic length field | `0x23284e0` (vaddr `0x25284e0`) | `0x17` | `0x14` |

(`report.meeting.tencent.com` exists in `.rodata` but has no entry in this
static table — it is constructed elsewhere and is a reporting-only surface, so
it is left untouched.)

### Patch 3 — channel identity `0300000000` → `1410000197`

The download channel is baked in as an 11-byte (string + NUL) constant. Servers
use it to decide which product is calling; the China id made VooV's auth
backend reject VooV-linked accounts. The VooV channel id has the same length,
so each site is replaced in place:

| Library | File offset |
| --- | --- |
| `lib/libwemeet_app_sdk.so` | `0x1c5bce0` |
| `lib/libwemeet.so` | `0x0d6538` |
| `bin/modules/schedule_meeting/libschedule_meeting_module.so` | `0x61d710` |

### Patch 4 — branding strings in the resource packs

UI strings live in the nxui resource packs as `{u32 length, UTF-8 bytes}`
entries. `VooV Meeting` is exactly the 12 UTF-8 bytes of `腾讯会议`, so the
replacement is length-preserving:

| Resource pack | Occurrences |
| --- | --- |
| `bin/wemeet.res` (window title among them) | 7 |
| `bin/modules/settings/module.res` | 3 |

Both packs are md5-checked at load time, so the 32-byte hex constants inside
the checking libraries are updated to the new digests:
`libwemeet_app_sdk.so` holds md5(`bin/wemeet.res`), and
`bin/modules/settings/libsettings_module.so` holds
md5(`bin/modules/settings/module.res`).

### Patch 5 — WeChat QR-login pages → VooV deployment

The WeChat-login webview loaded its QR page from `meeting.tencent.com`. After
the phone confirmed the scan, WeChat redirected through the China deployment's
callback, which could not match a VooV account — the phone showed `登录失败`.
Both login literals in `lib/libwemeet_module_api.so` are replaced with the
`voovmeeting.com` equivalents the genuine VooV client loads (shorter by four
bytes, NUL-padded in place):

| File offset | From | To |
| --- | --- | --- |
| `0x75a127` | `https://meeting.tencent.com/v2/qrcode-login?` | `https://voovmeeting.com/v2/qrcode-login?` |
| `0x75a154` | `https://meeting.tencent.com/v2/qrcode/auth?` | `https://voovmeeting.com/v2/qrcode/auth?` |

### Patch 6 — product identity `TM_Product_App` → `TM_Product_VooV`

The build identified itself as the Tencent Meeting product in two static
`std::string_view` constants (`{length, pointer}`). With `TM_Product_App`, the
native login flow treated a VooV-linked WeChat account as foreign and popped
the "already bound to a VooV Meeting account" dialog. The new string is one
byte longer, so each copy is relocated into a spare `.rodata` run and the view
and relocation addend are repointed:

| Library | Views (vaddr) | Relocations | Cave |
| --- | --- | --- | --- |
| `lib/libwemeet_app_components.so` | `0xc3d3d8`, `0xc3e3c8` | `0xe3d3e0`, `0xe3e3d0` | `0x98312c` |
| `lib/libwemeet_app_sdk.so` | `0x2328550` | `0x2528558` | `0x1b2e0e0` |

The relocation addends matter: the dynamic loader writes `base+addend` over
the data slot, so patching only the file bytes would leave the old pointer in
place.

### Patch 7 — deployment identity `TencentInside` → `Overseas`

Two more China-deployment defaults sit in the same `string_view` table as the
product type. The publish channel is sent as `c_app_publish_channel`, and the
China gateway rewrote every request as a Tencent Meeting login regardless of
`c_product_id`: a WeChat account already linked to VooV failed with
`-20003`. The genuine VooV builds send `c_app_publish_channel=Overseas` to
`https://api.voovmeeting.com` and complete the same login with `code: 0`. Both
replacements are shorter and NUL-padded; the view lengths are updated:

| Library | File offset | From → To | Views |
| --- | --- | --- | --- |
| `lib/libwemeet_app_sdk.so` | `0x1aa4d8c` | `TencentInside` → `Overseas` | `0x24e9e10`, `0x2511bb0`, `0x2511f20`, `0x25176b0`, `0x251d6c0`, `0x2528548` |
| `lib/libwemeet_app_sdk.so` | `0x1c5bbf8` | `https://work.medialab.qq.com` → `https://api.voovmeeting.com` | `0x25284f8` |

(View addresses are `.data.rel.ro` vaddrs; each length is the u64 immediately
before the relocated pointer.)

### Patch 8 — login page logo

The Linux build's nxres index only lists the Tencent Meeting login artwork.
The genuine VooV build ships the same bitmap in the same slot under a `_voov`
name, so the four `login_guide_logo.png` bitmaps (day/night, xhdpi/xxhdpi)
are replaced with that VooV artwork. The rest of the UI is untouched.

### Result

`scripts/patch-linux-build.py <extracted-tree>` applies the full patch set in
place, asserts original bytes and file sizes, NUL-pads or relocates every
replacement, updates the resource md5 constants, and is idempotent. Run against
a fresh extraction of the pristine `.deb` it produces the nine modified files
byte-identical (SHA-256) to the runtime-verified tree:

| File | Size | Original | Patched |
| --- | --- | --- | --- |
| `libwemeet_platform.so` | 28,364,080 B | `664b932a…6376e196` | `2308afe8…5e94f84` |
| `libwemeet_app_sdk.so` | 37,031,336 B | `554da86e…1f9bdd70` | `39b46e4f…0884177c` |

The patched client starts, renders, holds a stable TLS connection to
`conn.voovmeeting.com`, and **VooV account login works end-to-end**: scanning
the WeChat login QR code and confirming on the phone returns `code: 0` from
`https://api.voovmeeting.com/v2/account/login/auth-code` with the VooV
`userid`/`nick_name`, and the client lands on its home screen. The phone-number
form uses the same full 213-country dial-code list as the genuine VooV build
(the list is searchable — clearing the prefilled `+86` reveals every region).

The one non-binary fix is the launcher: on Wayland the client must run through
XWayland. Its X11 helper (`x_utils::SetStayOnTop` → `XInternAtom`) segfaults on
a Wayland `wl_display`, so `overlay/voov-meeting.sh` forces
`QT_QPA_PLATFORM=xcb`, `XDG_SESSION_TYPE=x11` and `WEMEET_XWAYLAND=1` — the
same environment as Tencent's own launcher.

### Still open

- **Meetings and media.** Joining a meeting, camera, microphone and screen
  sharing have not been verified yet (login is).
- **China update/report endpoints.** `report.meeting.tencent.com`,
  `updatecdn.meeting.qq.com`, the CDN and short-connection hosts are still the
  China deployment's; they are update/report surfaces, not the meeting channel.
- **Native Wayland.** The window is an XWayland client.
