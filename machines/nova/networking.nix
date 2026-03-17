{ ... }:
{
  networking.hostName = "nova";
  networking.networkmanager.enable = false;
  networking.interfaces.enp1s0.ipv4.addresses = [{
    address = "192.168.0.10";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.0.1";
  networking.nameservers = [ "1.1.1.1" ];

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [ 53 ]; # Pi-hole DNS — needs to be LAN-accessible
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
}