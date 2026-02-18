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
    allowedTCPPorts = [ 22 80 8096 ];
    allowedUDPPorts = [ 53 ];
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
}