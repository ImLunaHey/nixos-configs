{ pkgs }:
# Kept inside the standalone gateway flake so its deployment archive is complete.
# Home servers import this same pin; CI uses the identical upstream archive/hash.
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "netbird-client";
  version = "0.82.0";
  src = pkgs.fetchurl {
    url = "https://github.com/netbirdio/netbird/releases/download/v${version}/netbird_${version}_linux_amd64.tar.gz";
    sha256 = "b569f65de303d21317bc716f3116002e2cf175ae22a9f6d2bed91200a2f5000b";
  };
  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 netbird "$out/bin/netbird"
    mkdir -p "$out/share/licenses/netbird"
    cp -r LICENSE LICENSES "$out/share/licenses/netbird/"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/netbird" version)" = "${version}"
    runHook postInstallCheck
  '';
  meta = {
    description = "Pinned upstream NetBird client for managed Linux peers";
    homepage = "https://netbird.io";
    mainProgram = "netbird";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
    license = pkgs.lib.licenses.bsd3;
  };
}
