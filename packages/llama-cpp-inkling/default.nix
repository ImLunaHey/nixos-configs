{ pkgs }:
let
  kernels = import ./kernels.nix { inherit pkgs; };
in pkgs.cudaPackages_12_8.backendStdenv.mkDerivation {
  pname = "inkling-ik-server";
  version = "46b11f422d42-compat1";
  src = kernels.src;
  patches = [ ./server-compat.patch ];
  nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.patchelf ];
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail 'add_subdirectory(ggml)' 'add_library(ggml SHARED IMPORTED GLOBAL)
        set_target_properties(ggml PROPERTIES IMPORTED_LOCATION "${kernels}/lib/libggml.so" INTERFACE_INCLUDE_DIRECTORIES "'"$PWD"'/ggml/include" INTERFACE_COMPILE_DEFINITIONS "GGML_USE_CUDA" COMPILE_DEFINITIONS "GGML_USE_CUDA" LINK_LIBRARIES "")' \
      --replace-fail 'add_subdirectory(src)' 'add_library(llama SHARED IMPORTED GLOBAL)
        set_target_properties(llama PROPERTIES IMPORTED_LOCATION "${kernels}/lib/libllama.so" INTERFACE_INCLUDE_DIRECTORIES "'"$PWD"'/include;'"$PWD"'/src" INTERFACE_LINK_LIBRARIES ggml)' \
      --replace-fail 'install(TARGETS llama LIBRARY PUBLIC_HEADER)' ""
  '';
  NIX_LDFLAGS = "-rpath-link ${pkgs.cudaPackages_12_8.cuda_cudart}/lib/stubs";
  cmakeFlags = [ "-DLLAMA_CURL=OFF" "-DLLAMA_BUILD_TESTS=ON" ];
  ninjaFlags = [ "llama-server" "test-jinja" ];
  enableParallelBuilding = true;
  installPhase = ''
    mkdir -p $out/bin $out/lib
    cp bin/llama-server bin/test-jinja $out/bin/
    find . -name '*.so*' -type f -exec cp {} $out/lib/ \;
    for binary in $out/bin/* $out/lib/*; do
      patchelf --set-rpath "$out/lib:${kernels}/lib:${pkgs.lib.makeLibraryPath [ pkgs.cudaPackages_12_8.backendStdenv.cc.cc.lib ]}" "$binary"
    done
  '';
}
