{ ... }: {
  imports = [ ../gateway/telemetry-module.nix ];
  services.fleetTelemetry = {
    enable = true;
    bind = "100.94.41.124";
    interface = "enp3s0";
    firewallInterface = "tailscale0";
    client = "100.75.169.97";
  };
}
