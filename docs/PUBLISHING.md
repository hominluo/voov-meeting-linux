# Publishing

One build, every channel. The GitHub release is the source of truth: every
package is built from the same patched tree, and the store packages reuse the
release `.deb` so the payload is byte-identical everywhere.

| Channel | Artifact | Account needed | Status |
| ------- | -------- | -------------- | ------ |
| GitHub Releases | `.deb`, `.rpm`, `.AppImage`, `.flatpak`, APT index | GitHub | live |
| APT (Debian/Ubuntu) | `Packages`, `Release` + `.deb` | none | live |
| Nix flake | `flake.nix` | none | live |
| AUR (Arch) | `voov-meeting-bin` | AUR + SSH key | needs key |
| Fedora COPR | `packaging/fedora/voov-meeting.spec` | Fedora account + token | needs upload |
| openSUSE OBS | `packaging/opensuse/voov-meeting.spec` | OBS account | needs upload |
| Flathub | `packaging/flathub/*.yml` | GitHub (human PR) | needs PR |
| Snap Store | `packaging/snap/snapcraft.yaml` | Ubuntu One | needs upload |

## GitHub Releases

`scripts/build-*.sh` write into `dist/`, `scripts/make-apt-index.sh` writes the
APT index next to the packages, and everything is uploaded with:

```bash
gh release upload "v$PKG_VERSION" dist/* --clobber
```

`gh release upload --clobber` deletes the old asset before uploading, so a
failed upload can leave the release incomplete. Retry the file; the checksums
are in `dist/SHA256SUMS`.

## APT — Debian, Ubuntu

The release assets double as a flat APT repository. `releases/latest/download/`
always resolves to the newest release, and the `Packages` index sits next to
the `.deb`:

```bash
echo "deb [trusted=yes] https://github.com/hominluo/voov-meeting-linux/releases/latest/download/ ./" \
  | sudo tee /etc/apt/sources.list.d/voov-meeting.list
sudo apt update
sudo apt install voov-meeting
```

`trusted=yes` is needed because the flat repository has no signed `Release`.
The index, the `.deb` and the SHA-256 all travel over HTTPS, and APT verifies
the file against the checksum in `Packages`.

## AUR — Arch Linux

Package: [`voov-meeting-bin`](https://aur.archlinux.org/packages/voov-meeting-bin).

First publish:

```bash
# one-time: add ~/.ssh/aur.pub at https://aur.archlinux.org/account
git clone ssh://aur@aur.archlinux.org/voov-meeting-bin.git
cp packaging/aur/voov-meeting-bin/{PKGBUILD,.SRCINFO,voov-meeting-bin.install} voov-meeting-bin/
cd voov-meeting-bin
git add PKGBUILD .SRCINFO voov-meeting-bin.install
git commit -m "voov-meeting-bin 3.26.10.401-1"
git push
```

Every later release: bump `pkgver`, `pkgrel` and `sha256sums`, run
`makepkg --printsrcinfo > .SRCINFO`, commit, push.

## Fedora — COPR

The spec takes the release `.deb` as `Source0` and unpacks it, so COPR needs
no network beyond downloading that asset.

```bash
sudo dnf install copr-cli
copr-cli create voov-meeting --chroot fedora-44-x86_64 --chroot fedora-45-x86_64
copr-cli build voov-meeting packaging/fedora/voov-meeting.spec
```

Users then run:

```bash
sudo dnf copr enable hominluo/voov-meeting
sudo dnf install voov-meeting
```

The API token is created at <https://copr.fedorainfracloud.org/api/> and
stored in `~/.config/copr`.

## openSUSE — OBS

See `packaging/opensuse/README.md`. The spec is uploaded to an OBS project
(`home:hominluo`); OBS builds Tumbleweed and Leap repositories and users add
them with `zypper addrepo`.

## Flathub

Flathub stores manifests only. `packaging/flathub/io.github.hominluo.voov_meeting_linux.yml`
and `flathub.json` are copied to the root of a branch in a fork of
`flathub/flathub`, then a pull request is opened. See
`packaging/flathub/README.md`.

Note Flathub's policy: **AI agents must not open the submission PR or write
its commit message**; a human has to submit it, and the PR should disclose
that AI assistance was used.

## Snap Store

`packaging/snap/snapcraft.yaml` builds a classic-confinement snap named
`voov-meeting`. The name is free in the store; it needs a one-time
registration and, because classic confinement is a manual review, a
store-request approval. Build with the Snapcraft image if Snapcraft is not
installed:

```bash
docker run --rm -v "$PWD/packaging/snap:/project" ghcr.io/canonical/snapcraft:8_core22
snapcraft login
snapcraft register voov-meeting
snapcraft upload --release=stable packaging/snap/voov-meeting_3.26.10.401_amd64.snap
```

Classic approval: post in the Snapcraft forum *store-requests* category with
the snap name and the reason (the client needs the host's camera, microphone,
network and its own bundled Qt). Later uploads need no new request.

Users install with `sudo snap install voov-meeting`. The same `.snap`
is attached to the GitHub release, so it can also be installed without the
store: `sudo snap install --classic --dangerous ./voov-meeting_*.snap`.

## Nix

`flake.nix` wraps the release `.deb`; nothing to publish:

```bash
nix profile install github:hominluo/voov-meeting-linux
nix run github:hominluo/voov-meeting-linux
```

## Adding a channel

A new channel must not rebuild the payload. Take the release `.deb` (or the
patched tree it contains), install the desktop file, the hicolor icons and
`/opt/voov-meeting`, and declare the same runtime dependencies as
`packaging/deb/control.in`. The AUR and Fedora packages are the reference
implementations.
