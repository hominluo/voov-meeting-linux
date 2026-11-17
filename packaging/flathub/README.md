# Flathub submission

The manifest in this directory is the one that goes into the
[flathub/flathub](https://github.com/flathub/flathub) repository. Flathub
only stores manifests, so these two files are copied to the **root** of a
branch in a fork of that repository:

- `io.github.hominluo.voov_meeting_linux.yml`
- `flathub.json`

Everything else (the `.deb`, the AppStream metadata, the licence files) is
pulled from the URLs pinned in the manifest.

## Application ID

`io.github.hominluo.voov_meeting_linux` follows Flathub's code-hosting rule:
the ID must resolve to the repository URL, and
`io.github.hominluo.voov_meeting_linux` demangles to
`https://github.com/hominluo/voov-meeting-linux`. The same ID is used by
`scripts/build-flatpak.sh`, so the release bundle and the Flathub build are
the same application.

## Why the manifest installs a `.deb`

The payload is Tencent's proprietary Linux client. The `.deb` is the release
artifact built by this repository (patched binaries, VooV branding), and it is
extracted verbatim into `/app`, exactly like the `.deb`, RPM and Arch
packages do. The Flatpak therefore ships the same bits as every other
channel.

## Submitting

Flathub forbids AI agents from opening or automating submission pull
requests, so run these steps yourself:

```bash
gh repo fork flathub/flathub --clone=false
git clone --depth=1 https://github.com/<your-user>/flathub.git
cd flathub
git checkout -b io.github.hominluo.voov_meeting_linux
cp <this-repo>/packaging/flathub/io.github.hominluo.voov_meeting_linux.yml .
cp <this-repo>/packaging/flathub/flathub.json .
git add io.github.hominluo.voov_meeting_linux.yml flathub.json
git commit -m "Add VooV Meeting"
git push origin io.github.hominluo.voov_meeting_linux
gh pr create --repo flathub/flathub --title "Add io.github.hominluo.voov_meeting_linux" \
  --body "Unofficial native VooV Meeting client, repackaged from Tencent Meeting for Linux."
```

The Flathub CI builds the manifest and runs the linter. Expect questions
about:

- `--device=all` and `--filesystem=home` — the client uses camera,
  microphone, screen sharing and local file transfer directly, without
  portals.
- The VooV name and icon belong to Tencent; this is the real VooV client
  re-identified from Tencent's Linux build, not a wrapper.

## Test build locally

Needs `flatpak-builder`:

```bash
flatpak-builder --user --install --force-clean build-dir \
  io.github.hominluo.voov_meeting_linux.yml
flatpak run io.github.hominluo.voov_meeting_linux
```

The first build downloads the 189 MB `.deb`; the result is the same tree as
`dist/VooV-Meeting-3.26.10.401-1-x86_64.flatpak`.
