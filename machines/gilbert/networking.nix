{ ... }:
{
  networking.hostName = "gilbert";
  networking.networkmanager.enable = false;
  networking.interfaces.enp0s31f6.useDHCP = true;

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
}
