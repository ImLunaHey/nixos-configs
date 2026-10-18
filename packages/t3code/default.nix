{
  lib,
  stdenv,
  fetchurl,
  makeBinaryWrapper,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  version = "0.1.1-nightly.20261018.3285";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${finalAttrs.version}/t3-${finalAttrs.version}-linux-x64.tar.gz";
    hash = "sha256-IZ/E07er4QMRyecbE8YtgeJxebmfTt8gJwoyqASoRmA=";
  };

  sourceRoot = "t3-${finalAttrs.version}-linux-x64";

  nativeBuildInputs = [
    makeBinaryWrapper
    autoPatchelfHook
  ];
  buildInputs = [ stdenv.cc.cc.lib ];

  # The CLI is a Bun self-contained executable. Stripping it removes embedded
  # embedded program data and leaves a binary that crashes at startup.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/t3code" "$out/bin"
    cp -R . "$out/lib/t3code/"
    makeWrapper "$out/lib/t3code/t3" "$out/bin/t3"

    runHook postInstall
  '';

  meta = {
    description = "Minimal web GUI for coding agents";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [ "x86_64-linux" ];
  };
})
