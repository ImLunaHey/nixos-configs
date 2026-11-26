{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./anvil.nix
    ./board.nix
    ./cache.nix
    ./kache.nix
    ./lancache.nix
    ./monitoring.nix
    ./telemetry.nix
    ./display.nix
    ./netbird.nix
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
  boot.zfs.extraPools = [ "storage" ];

  # Claim the extra capacity after replacing pool drives with larger disks.
  services.zfs.expandOnBoot = [ "storage" ];

  services.zfs.autoScrub = {
    enable = true;
    interval = "weekly";
  };

  system.stateVersion = "26.05";

  services.homelab-agent.role = "nas / data lake";
  users.users.luna.extraGroups = [ "docker" ];
}
