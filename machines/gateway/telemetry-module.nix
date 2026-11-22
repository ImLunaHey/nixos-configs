{ config, lib, pkgs, ... }:
let
  cfg = config.services.fleetTelemetry;
  collector = pkgs.callPackage ./packages/hardware-telemetry { };
in {
  options.services.fleetTelemetry = {
    enable = lib.mkEnableOption "read-only Go fleet telemetry";
    bind = lib.mkOption { type = lib.types.str; };
    interface = lib.mkOption { type = lib.types.str; };
    client = lib.mkOption { type = lib.types.str; };
    firewallInterface = lib.mkOption { type = lib.types.str; };
    extraEnvironment = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = { }; };
    intelGPU = lib.mkEnableOption "Intel GPU performance counters";
  };
  config = lib.mkIf cfg.enable {
    networking.firewall.extraCommands = ''
      iptables -A nixos-fw -i ${cfg.firewallInterface} -s ${cfg.client} -p tcp --dport 8099 -j nixos-fw-accept
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D nixos-fw -i ${cfg.firewallInterface} -s ${cfg.client} -p tcp --dport 8099 -j nixos-fw-accept 2>/dev/null || true
    '';
    systemd.services.hardware-telemetry = {
      description = "Read-only Go hardware telemetry";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        METRICS_NAME = config.networking.hostName;
        METRICS_BIND = cfg.bind;
        METRICS_INTERFACE = cfg.interface;
        METRICS_ALLOWED_CLIENTS = "127.0.0.1,${cfg.client}";
      } // cfg.extraEnvironment;
      serviceConfig = {
        ExecStart = lib.getExe collector;
        DynamicUser = true;
        Restart = "always";
        RestartSec = "5s";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        AmbientCapabilities = lib.optionals cfg.intelGPU [ "CAP_PERFMON" ];
        CapabilityBoundingSet = lib.optionals cfg.intelGPU [ "CAP_PERFMON" ];
      };
      unitConfig.StartLimitIntervalSec = 0;
    };
  };
}
