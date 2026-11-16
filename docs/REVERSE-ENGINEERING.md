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
carried out as a patch spike; the next section documents the mechanism and the
verification evidence. It remains a binary patch against a proprietary client
that lags the desktop releases, and server-side acceptance of that build's
identity is still unverified.

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

### Result

`scripts/patch-linux-build.py <extracted-tree>` applies both patches in place,
asserts original bytes and file sizes, and is idempotent. Run against a fresh
extraction of the pristine `.deb` it produces libraries byte-identical
(SHA-256) to the hand-patched, runtime-verified ones:

| File | Size | Original | Patched |
| --- | --- | --- | --- |
| `libwemeet_platform.so` | 28,364,080 B | `664b932a…6376e196` | `2308afe8…5e94f84` |
| `libwemeet_app_sdk.so` | 37,031,336 B | `554da86e…1f9bdd70` | `050f969d…cebe6b` |

The patched client starts, renders, and holds a stable TLS connection to
`conn.voovmeeting.com`. The host CNAMEs to `voov-conn.vigtm-meeting-tencent.com`
and its certificate chains to `*.wemeet.tencent.com` — the same fleet behind the
VooV name.

### Still open

- **Server acceptance / login.** No VooV account has logged in through the
  patched build yet. The distribution channel baked into `libwemeet_app_sdk.so`
  remains `0300000000` (VooV Windows ships `1410000197`, one occurrence each,
  same length); if login is rejected, that constant is the next candidate.
- **Cosmetic China endpoints.** `report.meeting.tencent.com`,
  `meeting.tencent.com`, `updatecdn.meeting.qq.com`, `down.qq.com`,
  `wemeet-resupdate-…file.myqcloud.com`, `login/shortconn.im.qcloud.com` —
  update/report/CDN surfaces, not the meeting channel.
- **Branding.** The window title is still `腾讯会议`; VooV strings live in UI
  resources that have not been touched.
