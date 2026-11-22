{ pkgs, ... }:
let
  python = pkgs.python3.withPackages (p: [ p.psutil ]);
in
{
  # Bind only to Lake's tailnet address, never the LAN or public interfaces.
  systemd.services.hardware-telemetry = {
    description = "Read-only hardware telemetry for the fleet dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    environment = {
      METRICS_BIND = "100.94.132.48";
      METRICS_INTERFACE = "enp100s0f1np1";
      METRICS_SENSOR_FILE = "/run/lake-display/sensors.txt";
    };
    serviceConfig = {
      ExecStart = "${python}/bin/python ${../../modules/hardware-dashboard/server.py}";
      DynamicUser = true;
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
    unitConfig.StartLimitIntervalSec = 0;
  };
}
