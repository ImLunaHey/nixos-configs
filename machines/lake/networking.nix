{ ... }:
{
  networking.hostName = "lake";
  networking.networkmanager.enable = false;
  networking.interfaces.enp100s0f1np1.useDHCP = true;

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
    interfaces.enp100s0f1np1.allowedTCPPorts = [ 22 ];
  };
}
