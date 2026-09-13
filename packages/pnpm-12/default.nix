{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pnpm";
  version = "12.4.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@pnpm/exe.linux-x64/-/exe.linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-YU0YvcsSGoRMAmCzFddrc35oc0bAAbjgk/0KkyAsLWs=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 pnpm "$out/bin/pnpm"
    ln -s pnpm "$out/bin/pnpx"
    runHook postInstall
  '';

  meta = {
    description = "Fast, disk space efficient package manager";
    homepage = "https://pnpm.io";
    license = lib.licenses.mit;
    mainProgram = "pnpm";
    platforms = [ "x86_64-linux" ];
  };
})
