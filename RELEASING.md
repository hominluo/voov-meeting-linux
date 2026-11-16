# Release versioning

## Rule

Our release version follows the **Tencent Meeting for Linux version** the
client is built from (the upstream Linux client is versioned independently of
VooV's Windows/macOS releases), plus our own build counter:

| Our release      | Tencent Meeting (Linux) | Our build |
| ---------------- | ----------------------- | --------- |
| 3.26.10.401 (1)  | 3.26.10.401             | 1         |
| 3.26.10.401 (2)  | 3.26.10.401             | 2         |
| 3.27.x.x (1)     | 3.27.x.x                | 1         |

A new upstream Linux base resets the build number to `(1)`.

## Where it appears

Package formats and Git tags cannot contain spaces or parentheses, so the same
release is written as:

| Context               | Form                        |
| --------------------- | --------------------------- |
| GitHub release title  | `3.26.10.401 (1)`           |
| Git tag               | `v3.26.10.401-1`            |
| `.deb` / `.rpm`       | `3.26.10.401-1`             |
| Flatpak / AppImage    | `3.26.10.401-1` in the filename |

The trailing `-1` is the same build counter as `(1)`. The parenthesised form is
used wherever a human-readable version is allowed; everything else uses the
dash form so it stays a valid package version and filename.

## Bumping

1. Edit `TM_VERSION` / `BUILD_NUMBER` in `scripts/lib.sh`.
2. Update the `TM_DEB_*` constants (filename, size, MD5, SHA-256, URL).
   `scripts/prepare.sh` refuses a `.deb` whose size, MD5 or SHA-256 does not
   match the constants.
3. `scripts/patch-linux-build.py` asserts the exact sizes and original bytes
   of the two patched libraries. A new upstream base needs its offsets
   re-derived — the method is documented in
   [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md).
4. Update `pkgver` and the `.deb` checksum in `packaging/arch/PKGBUILD`.
5. Update the release notes in `docs/releases/`.

## Relationship to the application

The released application tree is Tencent's official **Tencent Meeting for
Linux** build with the VooV patches applied. The release version and the
application version are therefore the same number; only our build counter
differs.

## Replacing a broken release

Replace the assets of an existing tag when the tag's build is wrong but the
application version has not changed, rather than bumping the build counter:

```bash
gh release upload v3.26.10.401-1 dist/* --clobber
```

Bump `BUILD_NUMBER` only when users need both builds to coexist.