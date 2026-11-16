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
2. When moving to a new VooV release, also update `VOO_V_VERSION` and reset
   `BUILD_NUMBER=1`.
3. Update `UPSTREAM_VERSION` / `UPSTREAM_DEB` / `UPSTREAM_SHA256` if the Linux
   base package changed, then run `scripts/prepare.sh` and record the new
   checksums in `patches/patches.json`.

## Relationship to the base package

The released Linux application tree is Tencent Meeting **3.26.10.401** (the
latest Linux build Tencent ships). The VooV version describes the product line
this port targets, and is the version users see. Both are shown in
`README.md`, in the Debian package description, and in the release notes.
