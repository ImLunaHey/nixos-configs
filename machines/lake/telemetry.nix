{ pkgs, ... }:
let
  python = pkgs.python3.withPackages (p: [ p.psutil ]);
in
{
  # The hosts have separate tailnet visibility; admit only Tower over the LAN.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -i enp100s0f1np1 -s 10.0.0.161 -p tcp --dport 8099 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -i enp100s0f1np1 -s 10.0.0.161 -p tcp --dport 8099 -j nixos-fw-accept 2>/dev/null || true
  '';
  systemd.services.hardware-telemetry = {
    description = "Read-only hardware telemetry for the fleet dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    environment = {
      METRICS_BIND = "10.0.0.46";
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
