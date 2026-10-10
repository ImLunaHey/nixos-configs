{
  lib,
  stdenv,
  nodejs_24,
  pnpm_11,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeBinaryWrapper,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  version = "0.0.46-nightly.20261010.2922";

  src = ./.;
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    # The lockfile is reviewed and fully pinned; permit newly published
    # transitive releases rather than making the fixed-output fetch age-based.
    prePnpmInstall = "pnpm config set minimum-release-age 0";
    hash = "sha256-RCzvNsqArFNk/Cq+f8M0+6+jEJ+YgQZAR2Qz9jynLi0=";
  };

  nativeBuildInputs = [
    makeBinaryWrapper
    nodejs_24
    pnpm_11
    pnpmConfigHook
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  # The nightly CLI is a Bun self-contained executable. Stripping it removes
  # embedded program data and leaves a binary that crashes at startup.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/t3code" "$out/bin"
    cp -R node_modules "$out/lib/t3code/"

    makeWrapper ${lib.getExe nodejs_24} "$out/bin/t3" \
      --add-flags "$out/lib/t3code/node_modules/t3/bin/t3.js"

    runHook postInstall
  '';

  meta = {
    description = "Minimal web GUI for coding agents";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v0.0.46-nightly.20261010.2922";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = lib.platforms.linux;
  };
})
