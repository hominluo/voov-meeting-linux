# Fedora / COPR packaging

`voov-meeting.spec` builds the RPM straight from the release `.deb` on GitHub:
`%install` runs `ar x` on the .deb and unpacks its `data.tar.xz` into the
buildroot. No patched tree is needed, and `rpmbuild` itself needs no network
access: the spec's only external input is `Source0`, which `spectool` (locally)
or COPR downloads before the build.

## Local build

```bash
sudo dnf install rpm-build rpmdevtools binutils xz tar
rpmdev-setuptree
spectool -g -R packaging/fedora/voov-meeting.spec   # fetch the ~190 MB .deb
rpmbuild -bb packaging/fedora/voov-meeting.spec
# -> ~/rpmbuild/RPMS/x86_64/voov-meeting-3.26.10.401-1.fcXX.x86_64.rpm
```

## Publish via COPR

Put an API token from <https://copr.fedorainfracloud.org/api/> in
`~/.config/copr`, then:

```bash
sudo dnf install copr-cli
copr-cli create voov-meeting \
  --chroot fedora-44-x86_64 --chroot fedora-45-x86_64 \
  --description "Unofficial native VooV Meeting client"
copr-cli build voov-meeting packaging/fedora/voov-meeting.spec
```

`copr-cli build` accepts a local spec path: it uploads the spec, and COPR
downloads `Source0` from its full URL. Add one `--chroot` per Fedora release
(`copr-cli list-chroots` shows valid names), or use `-r <chroot>` to build in
a single chroot.

Web UI: create the project, then *Builds → New Build → Spec file* and give it
a public URL to this spec (for example the raw GitHub URL). The web UI cannot
read your disk, so push the spec first.

## New releases

`Source0` embeds `%{version}` and `%{reltag}`. Every new release therefore
needs all three:

1. a GitHub release tag `vX-Y` with the `voov-meeting_X-Y_amd64.deb` asset;
2. `%global tmver` / `%global reltag` bumped in this spec;
3. a new `copr-cli build`.

Anitya (release-monitoring.org) can watch the GitHub repo and report new
releases, but it does not edit the spec or trigger a COPR build — the version
bump and rebuild above are still manual.
