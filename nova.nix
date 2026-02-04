{ config, pkgs, ... }:

{
  # Hostname
  networking.hostName = "nova";
  networking.networkmanager.enable = true;

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 8096 ];  # SSH, Pi-hole, Jellyfin
    allowedUDPPorts = [ 53 ];  # DNS
  };

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Intel GPU for Jellyfin transcoding
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  system.stateVersion = "24.05";
}
