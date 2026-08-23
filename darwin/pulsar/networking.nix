{ lib, ... }:

let
  services = [ "Ethernet" "Wi-Fi" ];
in
{
  system.activationScripts.postActivation.text = lib.concatMapStringsSep "\n" (service: ''
    echo "configuring DHCP on '${service}'..." >&2
    if /usr/sbin/networksetup -listallnetworkservices | /usr/bin/grep -Fqx '${service}'; then
      if ! /usr/sbin/networksetup -getinfo '${service}' | /usr/bin/grep -Fqx 'DHCP Configuration'; then
        /usr/sbin/networksetup -setdhcp '${service}'
      fi
      /usr/sbin/networksetup -setdnsservers '${service}' Empty
    else
      echo "network service '${service}' not found; skipping DHCP configuration" >&2
    fi
  '') services;
}
