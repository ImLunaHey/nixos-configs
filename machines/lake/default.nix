{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./anvil.nix
    ./display.nix
    ./networking.nix
    ./samba.nix
    ./services.nix
    ./smartd.nix
    ./storage.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  services.zfs.autoScrub = {
    enable = true;
    interval = "weekly";
  };

  system.stateVersion = "26.05";

  services.homelab-agent.role = "nas / data lake";
}
