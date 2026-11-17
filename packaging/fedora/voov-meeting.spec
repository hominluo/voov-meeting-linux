# COPR spec for the unofficial VooV Meeting Linux build.
#
# Unlike packaging/rpm/voov-meeting.spec.in (which repacks a locally patched
# tree), this spec takes the release .deb straight from GitHub and unpacks its
# data.tar.xz. Everything below /opt/voov-meeting comes verbatim from that
# release asset, bundled Qt libraries included, so both debuginfo generation
# and rpm's automatic ELF dependency scanner are turned off.
#
# Build locally (Fedora):
#   sudo dnf install rpm-build rpmdevtools binutils xz tar
#   rpmdev-setuptree
#   spectool -g -R packaging/fedora/voov-meeting.spec
#   rpmbuild -bb packaging/fedora/voov-meeting.spec

%global tmver  3.26.10.401
%global reltag 1
%global url    https://github.com/hominluo/voov-meeting-linux

Name:           voov-meeting
Version:        %{tmver}
Release:        %{reltag}%{?dist}
Summary:        Unofficial native VooV Meeting Linux client (patched Tencent Meeting)
License:        LicenseRef-Proprietary
URL:            %{url}
Source0:        %{url}/releases/download/v%{version}-%{reltag}/voov-meeting_%{version}-%{reltag}_amd64.deb
BuildArch:      x86_64
ExclusiveArch:  x86_64

# The release .deb is the payload; only ar/tar are needed to unpack it.
BuildRequires:  binutils
BuildRequires:  tar
BuildRequires:  xz

# The payload is a prebuilt Qt application tree with its own copies of Qt,
# ICU, OpenSSL, etc. under /opt/voov-meeting/app/lib, which is not on the
# default library path. Let rpm record the runtime dependencies explicitly
# instead of guessing them from every bundled .so.
AutoReqProv:    no

Requires:       nss
Requires:       libX11
Requires:       libXrandr
Requires:       pulseaudio-libs
Requires:       libgcrypt
Requires:       dbus-libs
Requires:       systemd-libs
Requires:       desktop-file-utils
Requires:       hicolor-icon-theme
# AutoReqProv is off, so state the base runtime the launcher needs.
Requires:       glibc
Requires:       libstdc++
# /opt/voov-meeting/bin/voov-meeting is a bash script using env/readlink.
Requires:       bash
Requires:       coreutils
# System libraries that the bundled Qt/XCB/Wayland/WebEngine stack links
# against but does not ship; a minimal Fedora install lacks them.
Requires:       alsa-lib
Requires:       fontconfig
Requires:       libICE
Requires:       libSM
Requires:       libXtst
Requires:       libglvnd-egl
Requires:       libglvnd-glx
Requires:       libwayland-cursor
Requires:       libwayland-egl
Requires:       libwayland-server

Recommends:     xdg-utils
Recommends:     libnotify
Suggests:       pipewire

# No debuginfo for a repackaged proprietary binary tree, and no brp-strip:
# stripping the bundled Qt/ICU/OpenSSL libraries is not worth the risk.
%global debug_package %{nil}
%global __os_install_post %{nil}
# Keep the RPM reasonably small; zstd compresses the ~670 MB tree quickly
# enough for COPR.
%global _binary_payload w19.zstdio

%description
VooV Meeting is Tencent's international video-conferencing client.

Tencent ships VooV only for Windows and macOS; its official Linux client is
the China-only Tencent Meeting. This package takes that official client
(Tencent Meeting %{tmver} for Linux), patches its regional settings and
endpoint tables so it connects to VooV's servers, and packages it with native
Linux desktop integration. No Wine is involved.

This is an unofficial community build. The bundled application is proprietary
Tencent software; only the packaging and helper scripts are MIT licensed.

%prep
# Source0 is an ar(1) archive, not a tarball: create the build dir only.
%setup -q -c -T

%build
# Nothing to build; the payload is prebuilt.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cd %{_builddir}/%{name}-%{version}
ar x %{SOURCE0}
tar -xf data.tar.xz -C %{buildroot}

%post
if [ -x %{_bindir}/update-desktop-database ]; then
  %{_bindir}/update-desktop-database -q %{_datadir}/applications || :
fi
if [ -x %{_bindir}/gtk-update-icon-cache ]; then
  %{_bindir}/gtk-update-icon-cache -q -t -f %{_datadir}/icons/hicolor || :
fi

%postun
if [ -x %{_bindir}/update-desktop-database ]; then
  %{_bindir}/update-desktop-database -q %{_datadir}/applications || :
fi
if [ -x %{_bindir}/gtk-update-icon-cache ]; then
  %{_bindir}/gtk-update-icon-cache -q -t -f %{_datadir}/icons/hicolor || :
fi

%files
%defattr(-,root,root,-)
/opt/voov-meeting
%{_bindir}/voov-meeting
%{_datadir}/applications/voov-meeting.desktop
%{_datadir}/icons/hicolor/16x16/apps/voov-meeting.png
%{_datadir}/icons/hicolor/32x32/apps/voov-meeting.png
%{_datadir}/icons/hicolor/64x64/apps/voov-meeting.png
%{_datadir}/icons/hicolor/128x128/apps/voov-meeting.png
%{_datadir}/icons/hicolor/256x256/apps/voov-meeting.png
%{_datadir}/icons/hicolor/512x512/apps/voov-meeting.png
# 1024x1024 is not shipped by hicolor-icon-theme, so own those directories.
%dir %{_datadir}/icons/hicolor/1024x1024
%dir %{_datadir}/icons/hicolor/1024x1024/apps
%{_datadir}/icons/hicolor/1024x1024/apps/voov-meeting.png
%{_datadir}/icons/hicolor/scalable/apps/voov-meeting.svg
%{_datadir}/pixmaps/voov-meeting.png
%{_datadir}/doc/voov-meeting

%changelog
* Tue Nov 17 2026 Homin Luo <homin.ro@gmail.com> - 3.26.10.401-1
- COPR package built from the v3.26.10.401-1 release .deb
