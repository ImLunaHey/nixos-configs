{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./services.nix
    ./smartd.nix
    ./storage.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "26.05";

  services.homelab-agent.role = "nas / data lake";
}
