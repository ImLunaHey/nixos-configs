{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pnpm";
  version = "12.18.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@pnpm/exe.linux-x64/-/exe.linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-Z53y7t8Vj2OdttHwDnE9dm0NevxqkxvFFJemJdHhvfc=";
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
