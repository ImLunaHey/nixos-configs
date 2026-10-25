{
  fetchurl,
  lib,
  makeWrapper,
  stdenv,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "varlock";
  version = "1.23.0";

  src = fetchurl {
    url = "https://github.com/dmno-dev/varlock/releases/download/varlock%40${finalAttrs.version}/varlock-linux-x64.tar.gz";
    hash = "sha256-pA2Gzt3eLwMs2L3FlP7KdPYHVNAWFcGhEDHJ9MqX6O0=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Varlock is a Bun standalone executable. Patching its ELF interpreter moves
  # Bun's appended payload and turns it back into the plain Bun CLI, so invoke
  # the untouched binary through Nix's dynamic loader instead.
  dontPatchELF = true;

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 varlock "$out/libexec/varlock"
    install -Dm755 varlock-local-encrypt "$out/libexec/varlock-local-encrypt"
    makeWrapper ${stdenv.cc.bintools.dynamicLinker} "$out/bin/varlock" \
      --add-flags "--library-path ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}" \
      --add-flags "$out/libexec/varlock"
    runHook postInstall
  '';

  meta = {
    description = "Environment variable management and validation CLI";
    homepage = "https://varlock.dev";
    license = lib.licenses.mit;
    mainProgram = "varlock";
    platforms = [ "x86_64-linux" ];
  };
})
