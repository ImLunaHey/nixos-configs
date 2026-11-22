{ ... }:
{
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/tower-display"
  '';
  services.fleet-monitor = {
    enable = true;
    mode = "dashboard";
    name = "tower";
    interface = "enp7s0";
    title = "Homelab";
    featuredHost = "lake";
    hostOrder = [ "tower" "lake" "nova" "gateway" "pulsar" "comet" "gilbert" "void" ];
    compactHosts = [ "gateway" ];
    environment.NVIDIA_SMI = "/run/current-system/sw/bin/nvidia-smi";
    peers = {
      lake = "http://10.0.0.46:8099/api/metrics";
      nova = "http://10.0.0.178:8099/api/metrics";
      gateway = "http://10.0.0.46:8099/api/peers/gateway";
      pulsar = "http://10.0.0.107:8099/api/metrics";
      comet = "http://10.0.0.21:8099/api/metrics";
      gilbert = "http://100.115.201.122:8099/api/metrics";
      void = "http://100.94.41.124:8099/api/metrics";
    };
    healthChecks = { Inkling = "http://127.0.0.1:8080/health"; "T3 Code" = "http://127.0.0.1:3773/"; };
    kiosk = { enable = true; environment.WLR_DRM_DEVICES = "/dev/dri/tower-display"; };
  };
}
