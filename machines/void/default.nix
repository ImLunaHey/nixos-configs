{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./services.nix
    ./storage.nix
    ./smartd.nix
    ./samba.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  system.stateVersion = "24.05";

  # Disable auto-upgrade until boot regression is investigated
  system.autoUpgrade.enable = lib.mkForce false;
}
