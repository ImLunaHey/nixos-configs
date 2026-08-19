{ config, pkgs, ... }:
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

  services.homelab-agent.role = "nas / zfs raid";

  services.anvil-deployment-host = {
    enable = true;
    environment = "production";
    address = "100.94.41.124";
  };
}
