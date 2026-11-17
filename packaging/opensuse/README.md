# openSUSE (OBS)

The spec builds the release `.deb` into an RPM, so the payload is identical to
the Debian, Arch and Fedora packages.

Build locally:

```bash
cd packaging/opensuse
rpmbuild -bb --define "_sourcedir $PWD" --define "_rpmdir $PWD/out" voov-meeting.spec
```

Publish through the openSUSE Build Service:

1. Create a project at <https://build.opensuse.org> (e.g. `home:hominluo`).
2. Add the package `voov-meeting` and upload `voov-meeting.spec`.
3. OBS downloads `Source0` from the GitHub release, builds it for
   `openSUSE_Tumbleweed` and `openSUSE_Leap_16.0`, and serves a repository at
   `https://download.opensuse.org/repositories/home:/hominluo/<repo>/`.
4. Users install with:

   ```bash
   sudo zypper addrepo https://download.opensuse.org/repositories/home:/hominluo/openSUSE_Tumbleweed/home:hominluo.repo
   sudo zypper install voov-meeting
   ```

`osc` can also do the upload:

```bash
osc checkout home:hominluo
cd home:hominluo
mkdir voov-meeting && cp voov-meeting.spec voov-meeting/
cd voov-meeting && osc add voov-meeting.spec
osc commit -m "voov-meeting 3.26.10.401"
```
