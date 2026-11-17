# Flathub submission

The manifest in this directory is the one that goes into the
[flathub/flathub](https://github.com/flathub/flathub) repository. Flathub
only stores manifests, so **all** files in this directory except
`README.md` are copied to the root of a branch in a fork of that repository.

| File | Purpose |
| ---- | ------- |
| `io.github.hominluo.voov_meeting_linux.yml` | the manifest |
| `flathub.json` | x86_64 only |
| `apply_extra` | runs at install time, unpacks the `.deb` into `/app/opt` |
| `voov-meeting.sh` | `/app/bin/voov-meeting` wrapper |
| `voov-meeting.desktop` | desktop entry |
| `voov-256.png`, `voov-512.png`, `voov.svg` | icons |
| `io.github.hominluo.voov_meeting_linux.metainfo.xml` | AppStream metadata |
| `LICENSE`, `NOTICE` | licensing |

## Application ID

`io.github.hominluo.voov_meeting_linux` follows Flathub's code-hosting rule:
the ID must resolve to the repository URL, and
`io.github.hominluo.voov_meeting_linux` demangles to
`https://github.com/hominluo/voov-meeting-linux`. The same ID is used by
`scripts/build-flatpak.sh`, so the release bundle and the Flathub build are
the same application.

## Why extra-data

Tencent's client is proprietary, so the payload is declared as an
`extra-data` source: Flatpak downloads the release `.deb` from GitHub at
install time instead of Flathub redistributing the binaries. `apply_extra`
then unpacks only `/opt/voov-meeting` into `/app` using `python3` (to read
the `ar` archive) and `tar`. Flatpak only includes `python3` and `tar` from
the runtime, which is why `apply_extra` does not call `ar`.

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
cp <this-repo>/packaging/flathub/{apply_extra,voov-meeting.sh,voov-meeting.desktop,voov-256.png,voov-512.png,voov.svg} .
cp <this-repo>/packaging/flathub/io.github.hominluo.voov_meeting_linux.metainfo.xml .
cp <this-repo>/packaging/flathub/{LICENSE,NOTICE} .
git add io.github.hominluo.voov_meeting_linux.yml flathub.json apply_extra \
  voov-meeting.sh voov-meeting.desktop voov-256.png voov-512.png voov.svg \
  io.github.hominluo.voov_meeting_linux.metainfo.xml LICENSE NOTICE
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

The first install downloads the 197 MB `.deb` through `extra-data`; the
result is the same tree as `dist/VooV-Meeting-3.26.10.401-1-x86_64.flatpak`.
