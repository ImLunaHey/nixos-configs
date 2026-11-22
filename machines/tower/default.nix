{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
    ./networking.nix
    ./t3code.nix
  ];

  # Bootstrap without the existing hosts' SOPS/OAuth dependencies.
  homelabBase = {
    user = {
      name = "luna";
      passwordlessSudo = true;
      authorizedKeyFiles = [ ../../machines/gateway/admin.pub ];
    };
    ssh.enable = true;
    vpn.provider = "tailscale";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  services.fstrim.enable = true;

  # First installed using the 26.05 minimal ISO; retain across upgrades.
  system.stateVersion = "26.05";
}
