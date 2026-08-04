{ ... }:
{
  networking.hostName = "void";
  networking.networkmanager.enable = false;

  # TODO: update interface name after first boot (check with `ip link`)
  networking.interfaces.enp3s0.useDHCP = true;

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
    interfaces.enp3s0 = {
      # Allow SSH from LAN so we're not locked out if Tailscale is down
      allowedTCPPorts = [ 22 2049 111 445 139 ];
      allowedUDPPorts = [ 2049 111 137 138 ];
    };
  };
}
