{ lib, pkgs, ... }:
let
  plugins = import ../../packages/jellyfin-plugins { inherit pkgs; };
in {
  # Major upgrades require a stopped-state backup: rolling back the image alone
  # cannot undo a Jellyfin database migration. See infrastructure/README.md.
  virtualisation.oci-containers.containers.jellyfin.image =
    "jellyfin/jellyfin:12.4@sha256:fea863d0cd9ec445985d9c75fc6ed64e38a1d2766cf0c250a33d553f4fc1b771";

  systemd.services.docker-jellyfin = {
    preStart = lib.mkBefore ''
      ${pkgs.python3}/bin/python3 ${../../scripts/install-jellyfin-plugins.py} --source ${plugins}
    '';
    serviceConfig.TimeoutStartSec = 600;
  };
}
