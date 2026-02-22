{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./hardware.nix
    ./services.nix
    ./containers.nix
    ./storage.nix
    ./matrix.nix
    ./caddy.nix
    ../../modules/uptime-kuma.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  systemd.tmpfiles.rules = [
    "d /mnt/media 0755 root root -"
    "d /var/lib/jellyfin 0755 root root -"
    "d /var/lib/jellyfin/config 0755 root root -"
    "d /var/lib/jellyfin/cache 0755 root root -"
    "d /var/lib/pihole 0755 root root -"
    "d /var/lib/pihole/pihole 0755 root root -"
    "d /var/lib/pihole/dnsmasq 0755 root root -"
    "d /var/lib/uptime-kuma 0755 root root -"
  ];

  system.stateVersion = "24.05";

  services.uptime-kuma-sync.enable = true;
}