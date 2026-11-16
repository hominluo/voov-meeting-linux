#!/usr/bin/env python3
"""Apply the VooV Meeting Linux binary patches to an extracted app tree.

Every patch is checked twice: the input file must match a known SHA-256
(pristine or already-patched), and every byte range must match the expected
content before it is rewritten.  Running the script twice is safe.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "patches" / "patches.json"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tree", type=Path, help="extracted application tree (the directory that contains lib/, bin/, ...)")
    parser.add_argument("--check", action="store_true", help="only verify, do not modify")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    tree = args.tree.resolve()
    if not tree.is_dir():
        print(f"error: {tree} is not a directory", file=sys.stderr)
        return 1

    ok = True
    for entry in manifest["files"]:
        path = tree / entry["path"]
        if not path.is_file():
            print(f"error: missing {path}", file=sys.stderr)
            return 1

        digest = sha256(path)
        if digest == entry["sha256_patched"]:
            print(f"already patched: {entry['path']}")
            continue
        if digest != entry["sha256_original"]:
            print(
                f"error: {entry['path']} has unexpected SHA-256 {digest}\n"
                f"       expected original {entry['sha256_original']}\n"
                f"       or patched      {entry['sha256_patched']}",
                file=sys.stderr,
            )
            return 1

        data = bytearray(path.read_bytes())
        for patch in entry["patches"]:
            offset = int(patch["offset"], 16)
            original = bytes.fromhex(patch["original_hex"])
            patched = bytes.fromhex(patch["patched_hex"])
            if len(original) != len(patched):
                print(f"error: size mismatch in {patch['description']}", file=sys.stderr)
                return 1
            current = bytes(data[offset : offset + len(original)])
            if current != original:
                print(
                    f"error: {entry['path']}+{patch['offset']} contains {current.hex()}, "
                    f"expected {original.hex()}",
                    file=sys.stderr,
                )
                ok = False
                continue
            print(f"  {patch['offset']}: {patch['description']}")
            data[offset : offset + len(patched)] = patched

        if not ok or args.check:
            continue
        path.write_bytes(data)
        if sha256(path) != entry["sha256_patched"]:
            print(f"error: patched {entry['path']} does not match the recorded checksum", file=sys.stderr)
            return 1
        print(f"patched: {entry['path']}")

    for overlay in manifest["overlays"]:
        src = ROOT / overlay["source"]
        dst = tree / overlay["path"]
        if not src.is_file():
            print(f"error: missing overlay source {src}", file=sys.stderr)
            return 1
        if dst.is_file() and dst.read_bytes() == src.read_bytes():
            dst.chmod(0o755)
            print(f"already overlaid: {overlay['path']}")
            continue
        if not args.check:
            shutil.copyfile(src, dst)
            dst.chmod(0o755)
        print(f"{'would overlay' if args.check else 'overlaid'}: {overlay['path']}")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
