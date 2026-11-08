{ lib, pkgs, ... }:
let
  plugins = import ../../packages/jellyfin-plugins { inherit pkgs; };
in {
  # Major upgrades require a stopped-state backup: rolling back the image alone
  # cannot undo a Jellyfin database migration. See infrastructure/README.md.
  virtualisation.oci-containers.containers.jellyfin.image =
    "jellyfin/jellyfin:12.4@sha256:fea863d0cd9ec445985d9c75fc6ed64e38a1d2766cf0c250a33d553f4fc1b771";

  # Plugin configuration includes the OIDC client secret and other API tokens.
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin/config/plugins 0755 100000 100000 -"
    "d /var/lib/jellyfin/config/plugins/configurations 0700 100000 100000 -"
  ];

  systemd.services.docker-jellyfin = {
    preStart = lib.mkBefore ''
      ${pkgs.python3}/bin/python3 ${../../scripts/install-jellyfin-plugins.py} --source ${plugins}
      ${pkgs.python3}/bin/python3 ${../../scripts/configure-jellyfin-login.py} \
        --html ${../../infrastructure/jellyfin-login.html} \
        --css ${../../infrastructure/jellyfin-login.css} \
        --proxy-address "$(${pkgs.docker}/bin/docker network inspect media-net --format '{{(index .IPAM.Config 0).Gateway}}')"
    '';
    serviceConfig.TimeoutStartSec = lib.mkForce 600;
  };
}
