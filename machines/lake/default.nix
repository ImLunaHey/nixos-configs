{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./anvil.nix
    ./cache.nix
    ./lancache.nix
    ./monitoring.nix
    ./display.nix
    ./networking.nix
    ./samba.nix
    ./services.nix
    ./smartd.nix
    ./storage.nix
    ./t3code.nix
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
  users.users.luna.extraGroups = [ "docker" ];
}
