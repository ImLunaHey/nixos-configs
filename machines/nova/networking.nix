{ ... }:
{
  networking.hostName = "nova";
  networking.networkmanager.enable = false;
  networking.interfaces.enp1s0.useDHCP = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 53 ]; # Pi-hole DNS — needs to be LAN-accessible
    allowedUDPPorts = [ 53 ]; # Pi-hole DNS — needs to be LAN-accessible
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
}
