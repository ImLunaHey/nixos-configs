{ ... }: {
  imports = [ ../gateway/telemetry-module.nix ];
  services.fleetTelemetry = {
    enable = true;
    bind = "100.115.201.122";
    interface = "enp0s31f6";
    firewallInterface = "tailscale0";
    client = "100.75.169.97";
  };
}
