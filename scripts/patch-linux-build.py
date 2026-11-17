#!/usr/bin/env python3
"""Patch Tencent Meeting for Linux (China channel) into VooV Meeting.

Target build: TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb
              (sha256 70f37b029209c0ef91be9813eebf6650c6cb9a00f7c718490158773e2fe6acaf)

Binary patches, verified against the running client:

1. libwemeet_platform.so — default_settings() hook.
   wemeetsdk::utils::settings::default_settings() (vaddr 0x231940, .text is
   identity-mapped) is redirected to a code cave at 0x1706400 (an unreferenced
   NUL run inside the R+E LOAD segment). The cave reproduces the original
   function and then forces the two overseas flags in the returned settings
   object:

       lea    0x1d0c6b8(%rip),%rax        ; static default settings object
       mov    0x1d0cc48(%rip),%rcx        ; JSON-provided settings pointer
       test   %rcx,%rcx
       cmovne %rcx,%rax
       movb   $1,0x420(%rax)              ; overseas conn/endpoint selector
       movb   $1,0x4c8(%rax)              ; wemeetsdk::utils::version_util::IsVooVVersion()
       ret

   +0x4c8 is the field IsVooVVersion() reads; +0x420 gates InitSDK's
   conn-address replacement ("conn.voovmeeting.com" vs the China default).

2. libwemeet_app_sdk.so — static endpoint strings.
   The initial signaling address comes from a build-time std::string-like
   table in .data.rel.ro ({length, pointer} pairs), which pins the China
   endpoints regardless of any flag:
       .rodata 0x1c5bbc8: "conn.wemeet.tencent.com" -> "conn.voovmeeting.com"
       .rodata 0x1c5bbe0: "quic.conn.wemeet.qq.com" -> "quic.voovmeeting.com"
       .data.rel.ro 0x23284d0 / 0x23284e0: length 0x17 -> 0x14

3. Channel identity: 0300000000 -> 1410000197.
   The China channel id is baked into three libraries as an 11-byte
   (string + NUL) constant. Servers use it to pick the product: with the
   China id, VooV's own auth backend rejects VooV-linked accounts ("该账号已
   关联 VooV Meeting，无法使用腾讯会议"). The VooV id has the same length, so
   each site is replaced in place:
       libwemeet_app_sdk.so          @ 0x1c5bce0
       libwemeet.so                  @ 0x0d6538
       libschedule_meeting_module.so @ 0x61d710

4. Branding strings: 腾讯会议 -> VooV Meeting.
   UI strings live in the nxui resource packs as {u32 length, UTF-8 bytes}
   entries. "VooV Meeting" is exactly the 12 UTF-8 bytes of 腾讯会议, so the
   replacement is length-preserving and needs no reindexing:
       bin/wemeet.res                   7 occurrences (window title among them)
       bin/modules/settings/module.res  3 occurrences
   Both packs are md5-checked at load time ("expect md5:" /
   "md5 not matched ,wemeet.res file md5:" in libwemeet_framework.so), so the
   32-byte hex md5 constants inside the checking libraries are updated too:
       libwemeet_app_sdk.so    holds md5(bin/wemeet.res)
       libsettings_module.so   holds md5(bin/modules/settings/module.res)

5. WeChat QR-login pages: China deployment -> VooV deployment.
   The WeChat-login webview loads its QR page from the China deployment,
   https://meeting.tencent.com/v2/qrcode-login (wemeet_common::utils::login::
   GetMultiQrCodeUrl in libwemeet_module_api.so; the app-scan counterpart
   GetAuthQrCodeUrl is /v2/qrcode/auth?). After the phone confirms, WeChat
   redirects through the loading deployment's /v2/qrcode-login/wechat-callback,
   and the China backend cannot match a WeChat account linked to VooV — the
   phone shows 登录失败. Both literals are replaced with their voovmeeting.com
   equivalents (what the genuine VooV client loads; its callback completes the
   VooV login). Both are NUL-terminated C strings consumed through
   std::string(const char*), so the 4-byte-shorter replacements are
   NUL-padded in place:
       lib/libwemeet_module_api.so @ 0x75a127  https://voovmeeting.com/v2/qrcode-login?
       lib/libwemeet_module_api.so @ 0x75a154  https://voovmeeting.com/v2/qrcode/auth?

6. Client product identity: TM_Product_App -> TM_Product_VooV.
   The China build identifies itself as the Tencent Meeting product in two
   static std::string_view constants (libstdc++ layout: {length, pointer}).
   The VooV mac build uses TM_Product_VooV instead; with TM_Product_App the
   native login flow treats a VooV-linked WeChat account as foreign and pops
   the "This WeChat account is already bound to a VooV Meeting account" dialog.
   The new 15-byte string is one byte longer than the old one, so it is
   relocated into a NUL run and the view/relocation updated:
       lib/libwemeet_app_components.so  web-ticket access_type/product
           views 0xc3d3d8/0xc3d3e0, 0xc3e3c8/0xc3e3d0
           R_X86_64_RELATIVE relocations r_offset 0xe3d3e0/0xe3e3d0
           (addend = old string, points at the relocated copy)
           cave 0x98312c (spare tail of a .rodata filename slot)
       lib/libwemeet_app_sdk.so  InitSDK default settings (product type)
           view 0x2328550/0x2328558, relocation r_offset 0x2528558
           cave 0x1b2e0e0 (spare tail of a .rodata filename slot)
   The relocation addends matter: at load time the dynamic loader writes
   base+addend over the data slot, so patching only the file bytes would leave
   the old pointer in place.

7. Deployment identity: channel "TencentInside" -> "Overseas", CGI gateway
   work.medialab.qq.com -> api.voovmeeting.com.
   Two more China-deployment defaults sit in the same string_view table as the
   product type. The publish channel is sent as c_app_publish_channel, and the
   China gateway rewrites the request as a Tencent Meeting login regardless of
   c_product_id: a WeChat account already linked to VooV then fails with
   code -20003 ("该账号已关联 VooV Meeting，无法使用腾讯会议"). The genuine
   VooV builds send c_app_publish_channel=Overseas to https://api.voovmeeting.com
   and complete the same login with code 0. Both replacements are shorter and
   NUL-padded; the six/eight-byte view lengths in .data.rel.ro are updated:
       lib/libwemeet_app_sdk.so @ 0x1aa4d8c  TencentInside -> Overseas
           views 0x24e9e10, 0x2511bb0, 0x2511f20, 0x25176b0, 0x251d6c0, 0x2528548
       lib/libwemeet_app_sdk.so @ 0x1c5bbf8  https://work.medialab.qq.com
           -> https://api.voovmeeting.com, view 0x25284f8
   (view addresses are .data.rel.ro vaddrs; lengths are the u64 just before
   each relocated pointer.)

8. Login page logo: the login_guide_logo bitmaps (day/night, xhdpi/xxhdpi)
   are replaced with the VooV artwork that the genuine VooV build ships in
   the same nxres slot as login_guide_logo_voov.png. The Linux build's
   resource index has no _voov variants, so the plain slots are overwritten.

All other replacements are equal-length, so no ELF layout changes are needed.

Usage: patch-linux-build.py <extracted-wemeet-tree>
       (the directory containing lib/ and bin/, patched in place; idempotent)
"""

import hashlib
import struct
import sys
from pathlib import Path

ORIGINAL_SHA256 = {
    "libwemeet_platform.so": "664b932a0839a3ad8dc19dd0627f12635e21bf1253f763b18b27e8264376e196",
    "libwemeet_app_sdk.so": "554da86e823eeefde3b4c4ff5fd47d2c60ea7c676900692e08608a641f9bdd70",
}

# --- patch 1: default_settings hook ---------------------------------------------

DS_OFF = 0x231940          # file offset == vaddr in the R+E LOAD segment
DS_ORIG = bytes.fromhex(
    "488b0d01b3ad014885c9488d0567adad01480f45c1c3"  # function body (22 B)
    "662e0f1f840000000000"                          # alignment nop padding (10 B)
)
CAVE = 0x1706400           # unreferenced NUL run in .rodata (mapped R+E)
CAVE_LEN = 36

SETTINGS_GLOBAL = 0x1D0C6B8   # static default settings object (.bss)
SETTINGS_JSONPTR = 0x1D0CC48  # pointer set by SetDefaultSettingsByJson


def build_cave() -> bytes:
    def emit(insns):
        buf = bytearray()
        addr = CAVE
        fixes = []
        for code, target in insns:
            if target is not None:
                fixes.append((addr + len(code) - 4, target))
            buf += code
            addr += len(code)
        for pos, target in fixes:
            struct.pack_into("<i", buf, pos - CAVE, target - (pos + 4))
        return bytes(buf)

    return emit([
        (bytes.fromhex("488d05") + b"\0" * 4, SETTINGS_GLOBAL),  # lea  global(%rip),%rax
        (bytes.fromhex("488b0d") + b"\0" * 4, SETTINGS_JSONPTR),  # mov  ptr(%rip),%rcx
        (bytes.fromhex("4885c9"), None),                          # test %rcx,%rcx
        (bytes.fromhex("480f45c1"), None),                        # cmovne %rcx,%rax
        (bytes.fromhex("c6802004000001"), None),                  # movb $1,0x420(%rax)
        (bytes.fromhex("c680c804000001"), None),                  # movb $1,0x4c8(%rax)
        (bytes.fromhex("c3"), None),                              # ret
    ])


def patch_platform(path: Path) -> None:
    data = bytearray(path.read_bytes())
    assert len(data) == 28364080, f"unexpected size {len(data)}"
    expected_jmp = b"\xe9" + struct.pack("<i", CAVE - (DS_OFF + 5))
    if data[DS_OFF:DS_OFF + 5] == expected_jmp:
        print(f"  {path.name}: already patched")
        return
    assert bytes(data[DS_OFF:DS_OFF + len(DS_ORIG)]) == DS_ORIG, "default_settings bytes mismatch"
    assert all(b == 0 for b in data[CAVE:CAVE + CAVE_LEN]), "code cave is not empty"

    cave = build_cave()
    data[CAVE:CAVE + len(cave)] = cave
    rel = CAVE - (DS_OFF + 5)
    data[DS_OFF:DS_OFF + 5] = b"\xe9" + struct.pack("<i", rel)
    data[DS_OFF + 5:DS_OFF + 32] = b"\x90" * 27
    path.write_bytes(bytes(data))
    print(f"  {path.name}: hooked default_settings() (flags +0x420/+0x4c8 forced)")


# --- patch 2: app_sdk endpoint strings ------------------------------------------

APP_SDK_LEN = 37031336

CONN_STRING_OFF = 0x1C5BBC8
QUIC_STRING_OFF = 0x1C5BBE0
CONN_LENFIELD_OFF = 0x23284D0   # vaddr 0x25284d0 (file = vaddr - 0x200000)
QUIC_LENFIELD_OFF = 0x23284E0


def replace_slot(data: bytearray, off: int, old: str, new: str) -> None:
    oldb = old.encode() + b"\x00"
    newb = new.encode() + b"\x00"
    assert data[off:off + len(oldb)] == oldb, f"unexpected bytes at {hex(off)}"
    assert len(newb) <= len(oldb)
    data[off:off + len(newb)] = newb
    data[off + len(newb):off + len(oldb)] = b"\x00" * (len(oldb) - len(newb))


def patch_app_sdk_endpoints(path: Path) -> None:
    data = bytearray(path.read_bytes())
    assert len(data) == APP_SDK_LEN, f"unexpected size {len(data)}"
    if b"conn.voovmeeting.com" in bytes(data[CONN_STRING_OFF:CONN_STRING_OFF + 24]):
        print(f"  {path.name}: endpoints already patched")
        return
    replace_slot(data, CONN_STRING_OFF, "conn.wemeet.tencent.com", "conn.voovmeeting.com")
    replace_slot(data, QUIC_STRING_OFF, "quic.conn.wemeet.qq.com", "quic.voovmeeting.com")
    for off in (CONN_LENFIELD_OFF, QUIC_LENFIELD_OFF):
        cur, = struct.unpack_from("<Q", data, off)
        assert cur == 0x17, f"length field at {hex(off)} is {hex(cur)}"
        struct.pack_into("<Q", data, off, 0x14)
    path.write_bytes(bytes(data))
    print(f"  {path.name}: conn/quic endpoints -> voovmeeting.com")


# --- patch 3: channel identity ---------------------------------------------------

CHANNEL_CN = "0300000000"    # Tencent Meeting (China) channel id
CHANNEL_VOOV = "1410000197"  # VooV Meeting channel id

CHANNEL_LIBS = [
    "lib/libwemeet_app_sdk.so",
    "lib/libwemeet.so",
    "bin/modules/schedule_meeting/libschedule_meeting_module.so",
]


def patch_channel(path: Path) -> None:
    old = CHANNEL_CN.encode() + b"\x00"
    new = CHANNEL_VOOV.encode() + b"\x00"
    data = bytearray(path.read_bytes())
    n = data.count(old)
    if n == 0:
        assert data.count(new) >= 1, f"{path.name}: neither channel id found"
        print(f"  {path.name}: channel already patched")
        return
    assert n == 1, f"{path.name}: expected exactly one channel constant, found {n}"
    idx = data.index(old)
    data[idx:idx + len(new)] = new
    path.write_bytes(bytes(data))
    print(f"  {path.name}: channel {CHANNEL_CN} -> {CHANNEL_VOOV}")


# --- patch 4: branding strings + res md5 constants -------------------------------

TM_BRAND = "腾讯会议".encode()   # 12 UTF-8 bytes
VOOV_BRAND = b"VooV Meeting"     # 12 ASCII bytes

RES_SITES = [
    ("bin/wemeet.res", 7),
    ("bin/modules/settings/module.res", 3),
]

# <library holding the md5 constant, resource pack, md5 of the pristine pack>
MD5_SITES = [
    ("lib/libwemeet_app_sdk.so", "bin/wemeet.res",
     "85857ba7c4fc03de8ba81272e5062a8b"),
    ("bin/modules/settings/libsettings_module.so", "bin/modules/settings/module.res",
     "0da5ad8e3442be5cae9703fea9ff67ed"),
]


def patch_res_branding(root: Path) -> None:
    for rel, expected in RES_SITES:
        path = root / rel
        data = bytearray(path.read_bytes())
        n = data.count(TM_BRAND)
        if n == 0:
            # The China packs already mention VooV elsewhere (the "go use VooV
            # Meeting" login dialog), so the rebranded count is a lower bound.
            assert data.count(VOOV_BRAND) >= expected, f"{rel}: unexpected rebrand state"
            print(f"  {rel}: already rebranded")
            continue
        assert n == expected, f"{rel}: found {n} brand strings, expected {expected}"
        data = data.replace(TM_BRAND, VOOV_BRAND)
        path.write_bytes(bytes(data))
        print(f"  {rel}: {n} strings -> VooV Meeting")


# --- patch 8: login page logo -> VooV artwork ------------------------------------

# The Linux build's nxres only lists the Tencent Meeting login artwork. The
# genuine VooV build carries the same bitmap in the same slot under a _voov
# name (nxres/res/drawable-*/login_guide_logo_voov.png) and its resource index
# selects it by product; this build's resources.fb does not list those names,
# so the VooV bitmap is copied over the plain login_guide_logo slot.
LOGIN_LOGO_SITES = [
    ("drawable-xhdpi-v4/login_guide_logo.png", "login_guide_logo.xhdpi.png"),
    ("drawable-xxhdpi-v4/login_guide_logo.png", "login_guide_logo.xxhdpi.png"),
    ("drawable-night-xhdpi-v8/login_guide_logo.png", "login_guide_logo.night-xhdpi.png"),
    ("drawable-night-xxhdpi-v8/login_guide_logo.png", "login_guide_logo.night-xxhdpi.png"),
]


def patch_login_logo(root: Path) -> None:
    base = root / "bin" / "nxui" / "app" / "nxres" / "res"
    assets = Path(__file__).resolve().parent / "branding"
    for rel, asset in LOGIN_LOGO_SITES:
        dst = base / rel
        new = (assets / asset).read_bytes()
        if dst.read_bytes() == new:
            print(f"  {rel}: VooV logo already installed")
            continue
        dst.write_bytes(new)
        print(f"  {rel}: Tencent logo -> VooV artwork")


def patch_res_md5_constants(root: Path) -> None:
    for lib_rel, res_rel, orig_md5 in MD5_SITES:
        new_md5 = hashlib.md5((root / res_rel).read_bytes()).hexdigest().encode()
        path = root / lib_rel
        data = bytearray(path.read_bytes())
        old = orig_md5.encode()
        idx = data.find(old)
        if idx < 0:
            assert data.count(new_md5) == 1, f"{lib_rel}: md5 constant neither original nor updated"
            print(f"  {lib_rel}: {res_rel} md5 already updated")
            continue
        assert data.count(old) == 1, f"{lib_rel}: md5 constant not unique"
        data[idx:idx + 32] = new_md5
        path.write_bytes(bytes(data))
        print(f"  {lib_rel}: {res_rel} md5 -> {new_md5.decode()}")


# --- patch 5: WeChat QR-login pages -> VooV deployment ---------------------------

LOGIN_URL_SITES = [
    # file offset in lib/libwemeet_module_api.so, old URL, new URL
    (0x75A127, "https://meeting.tencent.com/v2/qrcode-login?",
               "https://voovmeeting.com/v2/qrcode-login?"),
    (0x75A154, "https://meeting.tencent.com/v2/qrcode/auth?",
               "https://voovmeeting.com/v2/qrcode/auth?"),
]


def patch_login_urls(path: Path) -> None:
    data = bytearray(path.read_bytes())
    patched = False
    for off, old, new in LOGIN_URL_SITES:
        oldb, newb = old.encode(), new.encode()
        pad = b"\x00" * (len(oldb) - len(newb))
        if data[off:off + len(oldb)] == oldb:
            data[off:off + len(newb)] = newb
            data[off + len(newb):off + len(oldb)] = pad
            patched = True
            print(f"  {path.name}: {old[8:]} -> {new[8:]}")
        else:
            assert data[off:off + len(newb)] == newb \
                and data[off + len(newb):off + len(oldb)] == pad, \
                f"unexpected bytes at {hex(off)}"
    if not patched:
        print(f"  {path.name}: login URLs already patched")
    path.write_bytes(bytes(data))


# --- patch 6: client product identity --------------------------------------------

PRODUCT_APP = b"TM_Product_App"
PRODUCT_VOOV = b"TM_Product_VooV"

APP_COMPONENTS_SIZE = 12938768          # 0xc56e10
AC_RELA_DYN = (0x1686A8, 0x3BFB8)
AC_STRING_VADDR = 0x9F9C5E              # original "TM_Product_App"
AC_VOOV_CAVE = 0x98312C                 # NUL run in .rodata (file == vaddr)
AC_VOOV_VIEWS = [                      # (length field, pointer field), file offsets
    (0xC3D3D8, 0xC3D3E0),
    (0xC3E3C8, 0xC3E3D0),
]
AC_VOOV_RELOCS = (0xE3D3E0, 0xE3E3D0)   # relocation r_offset (vaddr)

APP_SDK_SIZE = 37031336                 # 0x2350da8
SDK_RELA_DYN = (0x1F6070, 0xEE908)
SDK_STRING_VADDR = 0x1C5BC68           # original "TM_Product_App"
SDK_VOOV_CAVE = 0x1B2E0E0               # NUL run in .rodata (file == vaddr)
SDK_VOOV_VIEW = (0x2328550, 0x2328558)  # file offsets (vaddr = file + 0x200000)
SDK_VOOV_RELOC = 0x2528558             # relocation r_offset (vaddr)


def find_relocation(data: bytes, rela: tuple, r_offset: int) -> int:
    """Return the file offset of the RELA entry that targets r_offset."""

    start, size = rela
    hits = [o for o in range(start, start + size, 24)
            if struct.unpack_from("<Q", data, o)[0] == r_offset]
    assert len(hits) == 1, f"expected one relocation for {hex(r_offset)}, found {len(hits)}"
    return hits[0]


def relocate_product_view(data: bytearray, views: list, relocs: tuple, rela: tuple,
                          old_vaddr: int, cave: int) -> bool:
    """Move the product string of a {length, pointer} view into a NUL cave."""

    first = views[0][0]
    if struct.unpack_from("<Q", data, first)[0] == len(PRODUCT_VOOV) \
            and struct.unpack_from("<Q", data, first + 8)[0] == cave:
        return False
    for len_off, ptr_off in views:
        cur, = struct.unpack_from("<Q", data, len_off)
        assert cur == len(PRODUCT_APP), f"unexpected view length at {hex(len_off)}: {cur:#x}"
        assert struct.unpack_from("<Q", data, ptr_off)[0] == old_vaddr, \
            f"unexpected view pointer at {hex(ptr_off)}"
        struct.pack_into("<Q", data, len_off, len(PRODUCT_VOOV))
        struct.pack_into("<Q", data, ptr_off, cave)
    for r_offset in relocs:
        entry = find_relocation(data, rela, r_offset)
        addend, = struct.unpack_from("<q", data, entry + 16)
        assert addend & (2 ** 64 - 1) == old_vaddr, \
            f"unexpected relocation addend for {hex(r_offset)}"
        struct.pack_into("<q", data, entry + 16, cave)
    return True


def patch_product_views(path: Path) -> None:
    data = bytearray(path.read_bytes())
    name = path.name
    if name == "libwemeet_app_components.so":
        assert len(data) == APP_COMPONENTS_SIZE, f"unexpected size {len(data)}"
        args = (AC_VOOV_VIEWS, AC_VOOV_RELOCS, AC_RELA_DYN, AC_STRING_VADDR)
    else:
        assert len(data) == APP_SDK_SIZE, f"unexpected size {len(data)}"
        args = ([SDK_VOOV_VIEW], (SDK_VOOV_RELOC,), SDK_RELA_DYN, SDK_STRING_VADDR)
    cave = AC_VOOV_CAVE if name == "libwemeet_app_components.so" else SDK_VOOV_CAVE

    payload = PRODUCT_VOOV + b"\x00"
    changed = relocate_product_view(data, *args, cave=cave)
    if not changed:
        print(f"  {name}: product identity already patched")
        return
    assert all(b == 0 for b in data[cave:cave + len(payload)]), "product cave is not empty"
    data[cave:cave + len(payload)] = payload
    path.write_bytes(bytes(data))
    print(f"  {name}: product {PRODUCT_APP.decode()} -> {PRODUCT_VOOV.decode()}"
          f" (relocated to {hex(cave)})")


# --- patch 7: VooV deployment identity in the SDK defaults ------------------------
#
# The SDK defaults table (libwemeet_app_sdk.so) carries two more China-only
# values that decide which deployment the backend treats the client as:
#
#   c_app_publish_channel   TencentInside -> Overseas
#   CGI host                 work.medialab.qq.com -> api.voovmeeting.com
#
# The China CGI gateway overrides the product identity, so a client that sends
# c_product_id=TM_Product_VooV to work.medialab.qq.com still gets the Tencent
# Meeting login flow and fails with -20003 ("this WeChat account is bound to
# VooV Meeting"). Genuine VooV builds use "Overseas" and api.voovmeeting.com.
# Both values live in {length, pointer} string_view tables in .data.rel.ro.

SDK_DEFAULT_STRINGS = [
    (b"TencentInside", b"Overseas"),
    (b"https://work.medialab.qq.com", b"https://api.voovmeeting.com"),
]
SDK_DATA_RELRO = (0x22E0CE0, 0x24E0CE0)   # file offset, vaddr


def patch_default_string(data: bytearray, old: bytes, new: bytes) -> bool:
    assert len(new) <= len(old)
    start, size = SDK_RELA_DYN
    off_base, va_base = SDK_DATA_RELRO
    idx = data.find(old)
    padded = new + b"\x00" * (len(old) - len(new))
    if idx < 0:
        idx = data.find(padded)
        assert idx >= 0, f"neither {old!r} nor {new!r} found"
    else:
        assert data.find(old, idx + 1) < 0, f"{old!r} is not unique"
        data[idx:idx + len(old)] = padded
    updated = 0
    for entry in range(start, start + size, 24):
        addend, = struct.unpack_from("<q", data, entry + 16)
        if addend & (2 ** 64 - 1) != idx:
            continue
        r_offset, = struct.unpack_from("<Q", data, entry)
        len_off = off_base + (r_offset - va_base) - 8
        cur, = struct.unpack_from("<Q", data, len_off)
        assert cur in (len(old), len(new)), \
            f"unexpected view length for {new!r}: {cur}"
        struct.pack_into("<Q", data, len_off, len(new))
        updated += 1
    assert updated >= 1, f"no string_view references {old!r}"
    return updated


def patch_vvov_identity(path: Path) -> None:
    data = bytearray(path.read_bytes())
    assert len(data) == APP_SDK_SIZE, f"unexpected size {len(data)}"
    for old, new in SDK_DEFAULT_STRINGS:
        pending = old in data
        views = patch_default_string(data, old, new)
        state = f"{old.decode()} -> {new.decode()}" if pending \
            else f"{new.decode()} already patched"
        print(f"  {path.name}: {state} ({views} views)")
    path.write_bytes(bytes(data))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    for name in ("libwemeet_platform.so", "libwemeet_app_sdk.so"):
        path = root / "lib" / name
        if not path.exists():
            sys.exit(f"missing {path}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest == ORIGINAL_SHA256[name]:
            print(f"  {name}: original verified")
        else:
            print(f"  {name}: sha256 differs from the pristine build (patching an already-patched tree?)")
    patch_platform(root / "lib" / "libwemeet_platform.so")
    patch_res_branding(root)
    patch_app_sdk_endpoints(root / "lib" / "libwemeet_app_sdk.so")
    for rel in CHANNEL_LIBS:
        patch_channel(root / rel)
    patch_login_urls(root / "lib" / "libwemeet_module_api.so")
    patch_product_views(root / "lib" / "libwemeet_app_components.so")
    patch_product_views(root / "lib" / "libwemeet_app_sdk.so")
    patch_vvov_identity(root / "lib" / "libwemeet_app_sdk.so")
    patch_login_logo(root)
    patch_res_md5_constants(root)
    print("done")


if __name__ == "__main__":
    main()