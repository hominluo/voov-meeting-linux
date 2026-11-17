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
   of the patched binaries and resource packs. A new upstream base needs its
   offsets re-derived — the method is documented in
   [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md).
4. Update `pkgver` and the `.deb` checksum in `packaging/arch/PKGBUILD`, and
   the same fields in `packaging/aur/voov-meeting-bin/PKGBUILD` (then rerun
   `makepkg --printsrcinfo > .SRCINFO`).
5. Update the release notes in `docs/releases/`.
6. Update the `.deb` URL, size and checksum in
   `packaging/flathub/io.github.hominluo.voov_meeting_linux.yml` (pinned to an
   immutable commit for the metadata files).
7. Bump `Version`/`Source0` in `packaging/fedora/voov-meeting.spec` and
   `packaging/opensuse/voov-meeting.spec`, and `version` in
   `packaging/snap/snapcraft.yaml`.

## Publishing

Every release is built once and then published to each channel:

```bash
./scripts/build-deb.sh
./scripts/build-rpm.sh
./scripts/build-appimage.sh
./scripts/build-flatpak.sh
./scripts/make-apt-index.sh
```

Upload the packages, `SHA256SUMS`, and the APT index to the GitHub release:

```bash
gh release upload "v$PKG_VERSION" dist/* --clobber
```

The APT index (`Packages`, `Packages.gz`, `Packages.xz`, `Release`) must be
uploaded every time the `.deb` changes: the repository is the flat
`releases/latest/download/` directory, so `apt update` always sees the
current `Packages`.

Then, per channel:

| Channel | What to update |
| ------- | -------------- |
| AUR | bump `pkgver`/`pkgrel`/`sha256sums` in `packaging/aur/voov-meeting-bin`, rerun `makepkg --printsrcinfo`, commit and push to `ssh://aur@aur.archlinux.org/voov-meeting-bin.git` |
| Fedora COPR | `copr-cli build voov-meeting packaging/fedora/voov-meeting.spec` (or the web UI) |
| openSUSE OBS | `osc commit` the updated `voov-meeting.spec` in `home:hominluo` |
| Flathub | update the manifest's `.deb` URL/sha256 in a PR against `flathub/flathub` |
| Snap | `snapcraft pack` and `snapcraft upload --release=stable voov-meeting_*.snap` |

The Nix flake needs no publication: it fetches the pinned release `.deb` from
the GitHub release.

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