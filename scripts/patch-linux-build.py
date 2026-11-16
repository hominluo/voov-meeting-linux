#!/usr/bin/env python3
"""Patch Tencent Meeting for Linux (China channel) into VooV Meeting.

Target build: TencentMeeting_0300000000_3.26.10.401_x86_64_default.publish.officialwebsite.deb
              (sha256 70f37b029209c0ef91be9813eebf6650c6cb9a00f7c718490158773e2fe6acaf)

Two binary patches, both verified against the running client (the patched build
establishes its signaling connection to conn.voovmeeting.com instead of
conn.wemeet.tencent.com):

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

Both replacements fit inside the original string slots (shorter + NUL padding),
so no ELF layout changes are needed.

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


def patch_app_sdk(path: Path) -> None:
    data = bytearray(path.read_bytes())
    assert len(data) == APP_SDK_LEN, f"unexpected size {len(data)}"
    if b"conn.voovmeeting.com" in bytes(data[CONN_STRING_OFF:CONN_STRING_OFF + 24]):
        print(f"  {path.name}: already patched")
        return
    replace_slot(data, CONN_STRING_OFF, "conn.wemeet.tencent.com", "conn.voovmeeting.com")
    replace_slot(data, QUIC_STRING_OFF, "quic.conn.wemeet.qq.com", "quic.voovmeeting.com")
    for off in (CONN_LENFIELD_OFF, QUIC_LENFIELD_OFF):
        cur, = struct.unpack_from("<Q", data, off)
        assert cur == 0x17, f"length field at {hex(off)} is {hex(cur)}"
        struct.pack_into("<Q", data, off, 0x14)
    path.write_bytes(bytes(data))
    print(f"  {path.name}: conn/quic endpoints -> voovmeeting.com")


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
    patch_app_sdk(root / "lib" / "libwemeet_app_sdk.so")
    print("done")


if __name__ == "__main__":
    main()