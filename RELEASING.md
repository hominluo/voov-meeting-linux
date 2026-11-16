# Release versioning

## Rule

Our release version follows the **VooV Meeting product version**, not our own
0.x counter. Because the upstream product does not change between our rebuilds,
each of our updates appends a build number in parentheses:

| Our release    | VooV version | Our build |
| -------------- | ------------ | --------- |
| 3.43.0.510 (1) | 3.43.0.510   | 1         |
| 3.43.0.510 (2) | 3.43.0.510   | 2         |
| 3.44.0.520 (1) | 3.44.0.520   | 1         |

A new VooV version resets the build number to `(1)`.

## Where it appears

Package formats and Git tags cannot contain spaces or parentheses, so the same
release is written as:

| Context               | Form                                  |
| --------------------- | ------------------------------------- |
| GitHub release title  | `3.43.0.510 (1)`                      |
| Git tag               | `v3.43.0.510-1`                       |
| `.deb` / `.rpm`       | `3.43.0.510-1`                        |
| Flatpak / AppImage    | `3.43.0.510-1` in the filename       |

The trailing `-1` is the same build counter as `(1)`. The parenthesised form is
used wherever a human-readable version is allowed; everything else uses the
dash form so it stays a valid package version and filename.

## Bumping

1. Edit `BUILD_NUMBER` in `scripts/lib.sh` (`1`, `2`, ...).
2. When moving to a new VooV release, also update `VOO_V_VERSION`,
   `VOO_EXE`, `VOO_EXE_SIZE`, `VOO_EXE_MD5`, `VOO_EXE_SHA256`,
   `VOO_EXE_URL`, the DMG constants and reset `BUILD_NUMBER=1`.
3. Run `scripts/prepare.sh`; it refuses an installer whose size, MD5 or
   SHA-256 does not match the constants. Record the new manifest hash if it
   changed (the script prints it).
4. Update `pkgver` and the `.deb` checksum in `packaging/arch/PKGBUILD`.
5. Update the release notes in `docs/releases/`.

## Relationship to the application

The released application tree is VooV Meeting **3.43.0.510 for Windows**, the
build Tencent's official installer contains, running under Wine. The release
version and the application version are therefore the same number; only our
build counter differs.

## Replacing a broken release

Replace the assets of an existing tag when the tag's build is wrong but the
application version has not changed, rather than bumping the build counter:

```bash
gh release upload v3.43.0.510-1 dist/* --clobber
```

Bump `BUILD_NUMBER` only when users need both builds to coexist.
