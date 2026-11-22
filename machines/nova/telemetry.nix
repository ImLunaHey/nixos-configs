{ ... }: {
  imports = [ ../gateway/telemetry-module.nix ];
  services.fleetTelemetry = {
    enable = true;
    bind = "10.0.0.178";
    interface = "enp1s0";
    firewallInterface = "enp1s0";
    client = "10.0.0.161";
    intelGPU = true;
    extraEnvironment.INTEL_GPU_NAME = "Intel UHD · N100";
  };
}
