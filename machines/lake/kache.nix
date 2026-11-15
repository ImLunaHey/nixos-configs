{ pkgs, ... }:
let
  # The pinned nixpkgs package omits its system Zstd and SQLite dependencies.
  kache = pkgs.kache.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.pkg-config ];
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.zstd pkgs.sqlite ];
  });
  settings = (pkgs.formats.toml { }).generate "kache-config.toml" {
    cache = {
      local_only = true;
      local_max_size = "50GiB";
      gc_max_age_hours = 24 * 30;
      auto_recover_min_free_bytes = "20GiB";

      # Keep worktree cleanup explicit: these are separate from cache eviction.
      auto_recover_targets = false;
      auto_clean_orphaned_targets = false;
      auto_clean_idle_targets_days = 0;
      auto_clean_unused_units_days = 0;
    };
  };
  environment = {
    KACHE_CONFIG = "${settings}";
    RUSTC_WRAPPER = "${kache}/bin/kache";
  };
in
{
  environment.systemPackages = [ kache ];
  environment.etc."kache/config.toml".source = settings;
  environment.variables = environment;

  # The system service and its coding agents do not source login profiles.
  systemd.services.t3code.environment = environment;
  systemd.services.t3code.path = [ kache ];
}
