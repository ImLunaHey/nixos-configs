{ config, pkgs, ... }:

# Poll the repo and rebuild every 15 minutes, mirroring the NixOS hosts'
# `system.autoUpgrade`. Builds from the default branch's committed flake.lock,
# so updates land the same way the servers get them: commit → auto-applied.
let
  flake = "github:imlunahey/nixos-configs";
  host = config.networking.hostName;
  upgrade = pkgs.writeShellScript "darwin-auto-upgrade" ''
    export PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin
    exec darwin-rebuild switch --flake ${flake}#${host}
  '';
in
{
  launchd.daemons.darwin-auto-upgrade = {
    serviceConfig = {
      ProgramArguments = [ "${upgrade}" ];
      StartInterval = 900; # every 15 minutes
      RunAtLoad = false; # don't re-trigger a rebuild during activation
      StandardOutPath = "/var/log/darwin-auto-upgrade.log";
      StandardErrorPath = "/var/log/darwin-auto-upgrade.log";
    };
  };
}
