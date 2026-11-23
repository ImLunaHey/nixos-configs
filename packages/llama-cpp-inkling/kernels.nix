{ pkgs }:
let
  cuda = pkgs.cudaPackages_12_8;
  runtimePath = pkgs.lib.makeLibraryPath [ cuda.cuda_cudart cuda.libcublas cuda.backendStdenv.cc.cc.lib ];
in cuda.backendStdenv.mkDerivation {
  pname = "inkling-ik-experiment";
  version = "46b11f422d42";
  src = pkgs.fetchzip {
    url = "https://github.com/Mcniiby/ik_llama.cpp-mcniiby/archive/46b11f422d42ce4eb7cf8d92386cf36f60a1af86.tar.gz";
    sha256 = "1xbp9wp2s7zcak8pc844869cgpjdi50dzzcxpk6kwiq79hj5pimf";
  };
  nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.patchelf cuda.cuda_nvcc ];
  buildInputs = [ cuda.cuda_cudart cuda.libcublas ];
  cmakeFlags = [
    "-DGGML_CUDA=ON" "-DCMAKE_CUDA_ARCHITECTURES=120" "-DLLAMA_CURL=OFF"
    "-DGGML_NATIVE=OFF" "-DGGML_IQK_FA_ALL_QUANTS=OFF" "-DGGML_CUDA_FA_ALL_QUANTS=OFF"
    "-DGGML_CUDA_DEV_QUANTS=ON" "-DLLAMA_BUILD_TESTS=ON"
    "-DGGML_CUDA_DEV_QUANTS_TYPES=F32;F16;BF16;Q8_0;Q4_0;IQ4_NL;IQ3_S"
  ];
  ninjaFlags = [ "llama-server" "llama-bench" "test-ink-mix" "test-ink-control" "test-ink-prologue" "test-ink-epi" "test-fa-relbias" ];
  enableParallelBuilding = true;
  installPhase = ''
    mkdir -p $out/bin $out/lib
    cp bin/llama-server bin/llama-bench bin/test-ink-* bin/test-fa-relbias $out/bin/
    find . -name '*.so*' -type f -exec cp {} $out/lib/ \;
    for binary in $out/bin/* $out/lib/*; do
      patchelf --set-rpath "$out/lib:${runtimePath}:/run/opengl-driver/lib" "$binary"
    done
  '';
}
