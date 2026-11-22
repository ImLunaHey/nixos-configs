{ codex, aws-lc, zstd, oniguruma, sqlite, runCommand, lib }:

# aws-lc-sys must not mistake the separate OpenSSL dependency for AWS-LC.
codex.overrideAttrs (old: {
  buildInputs = (old.buildInputs or []) ++ [ aws-lc zstd oniguruma sqlite ];
  env = (old.env or {}) // {
    AWS_LC_SYS_SYSTEM_DIR = runCommand "aws-lc-system" {} ''
      mkdir -p "$out"
      ln -s ${lib.getDev aws-lc}/include/aws-lc "$out/include"
      ln -s ${lib.getLib aws-lc}/lib "$out/lib"
      ln -s ${lib.getDev aws-lc}/share "$out/share"
    '';
  };
})
