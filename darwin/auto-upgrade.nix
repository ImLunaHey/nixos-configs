{ config, lib, pkgs, ... }:

# Poll the repo and rebuild every 15 minutes, mirroring the NixOS hosts'
# `system.autoUpgrade`. Builds from the default branch's committed flake.lock,
# except for inputs a host explicitly opts into resolving independently.
let
  flake = "github:imlunahey/nixos-configs";
  host = config.networking.hostName;
  inputOverrideArguments = lib.concatLists (
    lib.mapAttrsToList (
      name: source: [ "--override-input" name source ]
    ) config.services.darwinAutoUpgrade.inputOverrides
  );
  inputOverrides = lib.optionalString (
    inputOverrideArguments != [ ]
  ) " ${lib.escapeShellArgs inputOverrideArguments}";
  upgrade = pkgs.writeShellScript "darwin-auto-upgrade" ''
    export PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin
    exec darwin-rebuild switch --refresh${inputOverrides} --flake ${flake}#${host}
  '';
in
{
  options.services.darwinAutoUpgrade.inputOverrides = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Flake inputs to resolve independently during each automatic upgrade.";
  };

  config = {
    launchd.daemons.darwin-auto-upgrade = {
      serviceConfig = {
        ProgramArguments = [ "${upgrade}" ];
        StartInterval = 900; # every 15 minutes
        RunAtLoad = false; # don't re-trigger a rebuild during activation
        StandardOutPath = "/var/log/darwin-auto-upgrade.log";
        StandardErrorPath = "/var/log/darwin-auto-upgrade.log";
      };
    };
  };
}
