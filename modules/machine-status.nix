# Startup and orderly-shutdown notifications for the personal NixOS fleet.
{ config, lib, pkgs, brrrNotify, ... }:
let
  host = config.networking.hostName;
  notify = title: message: level: sound:
    "${brrrNotify} ${lib.escapeShellArgs [ title message level sound "machine-${host}" ]}";
in
{
  systemd.services.machine-lifecycle-notify = {
    description = "Notify on machine startup and orderly shutdown";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    # Reverse stop ordering keeps networking and secrets available at shutdown.
    after = [ "network-online.target" "nss-lookup.target" "sops-install-secrets.service" "tailscaled.service" ];
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "45s";
      TimeoutStopSec = "45s";
    };
    script = notify "${host} started up" "${host} is online." "active" "bubbly_success_ding";
    preStop = ''
      # Manual stops and configuration changes are not machine shutdowns.
      if [ "$(${pkgs.systemd}/bin/systemctl is-system-running || true)" = stopping ]; then
        ${notify "${host} shutting down" "${host} is shutting down or rebooting." "time-sensitive" "warm_soft_error"}
      fi
    '';
  };
}
