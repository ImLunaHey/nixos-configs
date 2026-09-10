{
  lib,
  stdenv,
  nodejs_24,
  pnpm_11,
  fetchPnpmDeps,
  pnpmConfigHook,
  node-gyp,
  python3,
  makeBinaryWrapper,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  version = "0.0.40";

  src = ./.;
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    # The lockfile is reviewed and fully pinned; permit newly published
    # transitive releases rather than making the fixed-output fetch age-based.
    prePnpmInstall = "pnpm config set minimum-release-age 0";
    hash = "sha256-/8H+Air7SE6IWtdZDbEg6lSJuYWrItz1euaY99xtpzQ=";
  };

  nativeBuildInputs = [
    makeBinaryWrapper
    node-gyp
    nodejs_24
    pnpm_11
    pnpmConfigHook
    python3
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  buildPhase = ''
    runHook preBuild

    export npm_config_nodedir=${nodejs_24}
    export PYTHON=${lib.getExe python3}
    pty_dir=$(find node_modules/.pnpm -path '*/node-pty@*/node_modules/node-pty' -type d -print -quit)
    if [ -z "$pty_dir" ]; then
      echo "node-pty source was not installed" >&2
      exit 1
    fi
    node-gyp rebuild --directory "$pty_dir"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/t3code" "$out/bin"
    cp -R node_modules "$out/lib/t3code/"

    makeWrapper ${lib.getExe nodejs_24} "$out/bin/t3" \
      --add-flags "$out/lib/t3code/node_modules/t3/dist/bin.mjs"

    runHook postInstall
  '';

  meta = {
    description = "Minimal web GUI for coding agents";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v0.0.40";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = lib.platforms.linux;
  };
})
