{ ... }:
{
  networking.hostName = "gilbert";
  networking.networkmanager.enable = false;
  networking.interfaces.enp0s31f6.ipv4.addresses = [{
    address = "192.168.0.11";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.0.1";
  networking.nameservers = [ "1.1.1.1" ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 8080 2049 ];
    allowedUDPPorts = [ 2049 ];
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
}