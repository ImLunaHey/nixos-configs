{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./hardware.nix
    ./services.nix
    ./containers.nix
    ./storage.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = [ "sg" ];

  systemd.tmpfiles.rules = [
    "d /mnt/media 0755 root root -"
    "d /mnt/media/config 0755 1000 1000 -"
    "d /mnt/media/logs 0755 1000 1000 -"
    "d /mnt/media/completed 0755 1000 1000 -"
    "d /mnt/media/completed/movies 0755 1000 1000 -"
    "d /mnt/media/completed/tv 0755 1000 1000 -"
    "d /mnt/media/raw 0755 1000 1000 -"
    "d /mnt/media/transcode 0755 1000 1000 -"
    "d /mnt/media/transcode/movies 0755 1000 1000 -"
    "d /mnt/media/transcode/tv 0755 1000 1000 -"
    "d /mnt/media/db 0755 1000 1000 -"
  ];

  system.stateVersion = "24.05";
}