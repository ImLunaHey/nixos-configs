{ ... }:
{
  networking.hostName = "void";
  networking.networkmanager.enable = false;

  # TODO: update interface name after first boot (check with `ip link`)
  networking.interfaces.enp3s0.ipv4.addresses = [{
    address = "192.168.0.12";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.0.1";
  networking.nameservers = [ "1.1.1.1" ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 2049 ];   # SSH, NFS
    allowedUDPPorts = [ 2049 ];
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };
}
