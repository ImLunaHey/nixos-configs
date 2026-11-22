{ ... }:
{
  networking.hostName = "tower";
  networking.useDHCP = true;
  networking.firewall = {
    enable = true;
    checkReversePath = "loose";
    # SSH is also available on the LAN before Tailscale enrolment.
    allowedTCPPorts = [ 22 ];
    interfaces.enp7s0.allowedTCPPorts = [ 3773 ];
    interfaces.tailscale0.allowedTCPPorts = [ 3773 ];
  };
}
