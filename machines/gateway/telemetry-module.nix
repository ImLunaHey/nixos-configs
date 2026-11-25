{ config, lib, pkgs, ... }:
let
  cfg = config.services.fleetTelemetry;
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
    services.fleet-monitor = {
      enable = true;
      processes.enable = true;
      mode = "agent";
      listenAddress = cfg.bind;
      interface = cfg.interface;
      allowedClients = [ "127.0.0.1" cfg.client ];
      intelGPU = cfg.intelGPU;
      environment = cfg.extraEnvironment;
    };
  };
}
