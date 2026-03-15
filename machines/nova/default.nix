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
    ../../modules/cloudflare-dns.nix
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
    "d /var/lib/rustfs/data 0755 10001 10001 -"
    "d /var/lib/rustfs/logs 0755 10001 10001 -"
    "d /var/lib/romm-db 0755 root root -"
    "d /var/lib/romm 0755 root root -"
    "d /var/lib/romm/resources 0755 root root -"
    "d /var/lib/romm/redis-data 0755 root root -"
    "d /var/lib/romm/assets 0755 root root -"
    "d /var/lib/romm/config 0755 root root -"
  ];

  system.stateVersion = "24.05";

  services.uptime-kuma-sync.enable = true;

  services.cloudflare-dns = {
    enable = true;
    zone = "flaked.org";
    ip = "100.106.184.73";
  };
}