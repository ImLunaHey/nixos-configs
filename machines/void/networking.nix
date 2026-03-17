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
    extraRules = ''
      iptables -A nixos-fw -p tcp --dport 2049 -s 192.168.0.10 -j ACCEPT
      iptables -A nixos-fw -p udp --dport 2049 -s 192.168.0.10 -j ACCEPT
    '';
  };
}
