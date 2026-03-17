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
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
    # NFS restricted to nova only
    extraInputRules = ''
      ip saddr 192.168.0.10 tcp dport 2049 accept
      ip saddr 192.168.0.10 udp dport 2049 accept
    '';
  };
}
