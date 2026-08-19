{ ... }:

# Static LAN IP for pulsar, continuing the server scheme
# (nova .10, gilbert .11, void .12 → pulsar .13).
#
# macOS has no declarative equivalent to NixOS's networking.interfaces, so this
# drives `networksetup` from a post-activation script. It's guarded: if the
# named network service doesn't exist (e.g. the mini is on Wi-Fi, not Ethernet),
# it logs and skips rather than breaking activation. Change `service` below to
# match — list options on the machine with:
#   networksetup -listallnetworkservices
let
  service = "Ethernet";
  address = "192.168.0.13";
  netmask = "255.255.255.0";
  gateway = "192.168.0.1";
  dns = "1.1.1.1";
in
{
  system.activationScripts.postActivation.text = ''
    echo "configuring static IP (${address}) on '${service}'..." >&2
    if /usr/sbin/networksetup -listallnetworkservices | grep -qx '${service}'; then
      /usr/sbin/networksetup -setmanual '${service}' ${address} ${netmask} ${gateway}
      /usr/sbin/networksetup -setdnsservers '${service}' ${dns}
    else
      echo "network service '${service}' not found; skipping static IP" >&2
    fi
  '';
}
