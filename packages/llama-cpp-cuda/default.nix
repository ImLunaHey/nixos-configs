{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper, openssl, curl, zlib }:

# This release includes the merged Inkling 2 loop architecture. Keep the CUDA
# runtime and executables on the same release; 12.8 supports Blackwell and the
# driver already deployed on Tower.
stdenv.mkDerivation rec {
  pname = "llama-cpp-cuda";
  version = "b12633";
  src = fetchurl {
    url = "https://github.com/ggml-org/llama.cpp/releases/download/${version}/llama-${version}-bin-ubuntu-cuda-12.8-x64.tar.gz";
    sha256 = "627ba16f9f9966ed5e7752379391d1a33be7104acef3448957c5e55b450dbd38";
  };
  cudaRuntime = fetchurl {
    url = "https://github.com/ggml-org/llama.cpp/releases/download/${version}/cudart-llama-${version}-bin-ubuntu-cuda-12.8-x64.tar.gz";
    sha256 = "4f3ab78c901bc534924223124426b8fe6a854de094ef9f0fb7c109d4aa4f478e";
  };
  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib openssl curl zlib ];
  autoPatchelfIgnoreMissingDeps = [ "libcuda.so.1" ];
  appendRunpaths = [ "/run/opengl-driver/lib" ];
  dontBuild = true;
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xzf "$src" -C source
    tar -xzf "$cudaRuntime" -C source
    cd source
    runHook postUnpack
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/bin"
    find . -name '*.so*' -exec cp -P {} "$out/lib/" \;
    # ggml discovers backends beside the real executable, not through the
    # dynamic linker's library search path.
    find . -type f -name llama-server -exec cp {} "$out/lib/" \;
    addAutoPatchelfSearchPath "$out/lib"
    makeWrapper "$out/lib/llama-server" "$out/bin/llama-server" \
      --prefix LD_LIBRARY_PATH : "$out/lib:/run/opengl-driver/lib"
    runHook postInstall
  '';
  meta = {
    description = "Pinned CUDA llama.cpp server with Inkling 2 Mini support";
    homepage = "https://github.com/ggml-org/llama.cpp";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "llama-server";
  };
}
