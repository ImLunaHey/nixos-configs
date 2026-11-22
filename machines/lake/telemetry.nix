{ pkgs, ... }:
{
  imports = [ ../gateway/telemetry-module.nix ];
  services.fleetTelemetry = {
    enable = true;
    bind = "10.0.0.46";
    interface = "enp100s0f1np1";
    firewallInterface = "enp100s0f1np1";
    client = "10.0.0.161";
    extraEnvironment = {
      METRICS_SENSOR_FILE = "/run/lake-display/sensors.txt";
      AMD_GPU_NAME = "Radeon 780M · integrated";
      METRICS_ZFS_POOL = "storage";
      ZPOOL = "${pkgs.zfs}/bin/zpool";
      ZFS = "${pkgs.zfs}/bin/zfs";
      DASHBOARD_PEERS = builtins.toJSON { gateway = "http://100.66.248.2:8099/api/metrics"; };
    };
  };
}
