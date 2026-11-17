#
# openSUSE / OBS spec for the unofficial native VooV Meeting client.
# The payload is the release .deb; it is unpacked verbatim so the result is
# identical to the other distributions' packages.
#
Name:           voov-meeting
Version:        3.26.10.401
Release:        1
Summary:        Unofficial native VooV Meeting client (patched Tencent Meeting)
License:        LicenseRef-Proprietary
Group:          Productivity/Networking/InstantMessaging
URL:            https://github.com/hominluo/voov-meeting-linux
Source0:        https://github.com/hominluo/voov-meeting-linux/releases/download/v%{version}-1/voov-meeting_%{version}-1_amd64.deb
BuildArch:      x86_64
AutoReqProv:    no

BuildRequires:  binutils
BuildRequires:  xz
BuildRequires:  tar

Requires:       mozilla-nss
Requires:       libX11-6
Requires:       libXrandr2
Requires:       libpulse0
Requires:       libgcrypt20
Requires:       dbus-1
Requires:       systemd
Requires:       desktop-file-utils

%global debug_package %{nil}
%global __strip /bin/true
%global __os_install_post %{nil}
# The payload is ~670 MB of prebuilt binaries; use the same zstd payload
# compression as the Fedora package.
%global _binary_payload w19.zstdio

%description
Tencent ships VooV only for Windows and macOS.  This package republishes
Tencent's official Linux client with small binary patches that switch it to
VooV's regional settings and endpoints.  It runs natively, without Wine.

%prep

%build

%install
mkdir -p %{buildroot}/tmp/deb
cd %{buildroot}/tmp/deb
ar x %{SOURCE0}
tar -xf data.tar.xz -C %{buildroot}
rm -rf %{buildroot}/tmp

%post
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q %{_datadir}/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f %{_datadir}/icons/hicolor || :
fi

%postun
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q %{_datadir}/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f %{_datadir}/icons/hicolor || :
fi

%files
/opt/voov-meeting
/usr/bin/voov-meeting
/usr/share/applications/voov-meeting.desktop
/usr/share/icons/hicolor
/usr/share/pixmaps/voov-meeting.png
%doc /usr/share/doc/voov-meeting/copyright

%changelog
* Mon Nov 16 2026 Homin Luo <homin.ro@gmail.com> - 3.26.10.401-1
- Initial package, built from Tencent Meeting 3.26.10.401.
