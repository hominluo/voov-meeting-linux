{ lib
, stdenvNoCC
, fetchurl
, dpkg
, makeWrapper
, libGL
, libx11
, libxrandr
, libxext
, libxrender
, libxi
, libxtst
, libxcursor
, libxfixes
, libxcb
, libxkbcommon
, libpulseaudio
, nss
, nspr
, libgcrypt
, dbus
, systemd
, fontconfig
, freetype
, expat
, glib
, zlib
, libpng
, wayland
, alsa-lib
, libdrm
, libgbm
, libXcomposite
, libXdamage
, libxshmfence
, libXScrnSaver
, libXxf86vm
, libXt
, libSM
, libICE
, libXmu
, libXpm
, libxkbfile
, harfbuzz
, xcbutil
, xcbutilcursor
, xcbutilimage
, xcbutilkeysyms
, xcbutilrenderutil
, xcbutilwm
, cups
, stdenv
}:

stdenvNoCC.mkDerivation rec {
  pname = "voov-meeting";
  version = "3.26.10.401";

  src = fetchurl {
    url = "https://github.com/hominluo/voov-meeting-linux/releases/download/v${version}-1/voov-meeting_${version}-1_amd64.deb";
    hash = "sha256-Fq94DHJ5KcLSOswb775DTrI4C9UjPnyfvcrEucTKryE=";
  };

  nativeBuildInputs = [ dpkg makeWrapper ];

  dontUnpack = true;
  dontPatchELF = true;
  dontStrip = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dpkg-deb -x "$src" "$out"
    rm -f "$out/usr/bin/voov-meeting"
    rmdir "$out/usr/bin" 2>/dev/null || true

    mkdir -p "$out/share"
    cp -a "$out/usr/share/." "$out/share/"
    rm -rf "$out/usr"

    substituteInPlace "$out/share/applications/voov-meeting.desktop" \
      --replace-fail "Exec=/opt/voov-meeting/bin/voov-meeting" "Exec=$out/bin/voov-meeting" \
      --replace-fail "Icon=voov-meeting" "Icon=$out/share/icons/hicolor/512x512/apps/voov-meeting.png"

    makeWrapper "$out/opt/voov-meeting/bin/voov-meeting" "$out/bin/voov-meeting" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        libGL libx11 libxrandr libxext libxrender libxi libxtst libxcursor
        libxfixes libxcb libxkbcommon libpulseaudio nss nspr libgcrypt dbus
        systemd fontconfig freetype expat glib zlib libpng stdenv.cc.cc.lib
        wayland alsa-lib libdrm libgbm libXcomposite libXdamage libxshmfence
        libXScrnSaver cups harfbuzz libXxf86vm libXt libSM libICE libXmu libXpm
        libxkbfile xcbutil xcbutilcursor xcbutilimage xcbutilkeysyms
        xcbutilrenderutil xcbutilwm
      ]}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Unofficial native VooV Meeting client (patched Tencent Meeting)";
    homepage = "https://github.com/hominluo/voov-meeting-linux";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "voov-meeting";
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
}
