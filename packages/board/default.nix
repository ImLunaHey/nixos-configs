{ buildNpmPackage, nodejs_24, makeWrapper, lib }:
buildNpmPackage {
  pname = "vercel-board";
  version = "0.54.0";
  src = ./.;
  nodejs = nodejs_24;
  npmDepsHash = "sha256-oZxuB11EJ5nsbAz9LQnAecJrH5dplC+WDzmN2DvgsN4=";
  npmFlags = [ "--omit=optional" ];
  dontNpmBuild = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/board" "$out/bin"
    cp -r node_modules "$out/lib/board/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/board" \
      --add-flags "$out/lib/board/node_modules/@vercel/board/dist/cli.mjs"
    ln -s board "$out/bin/vb"
    runHook postInstall
  '';
  meta = {
    description = "Self-hosted message board and CLI for coding agents";
    homepage = "https://github.com/vercel/board";
    license = lib.licenses.asl20;
    mainProgram = "board";
  };
}
