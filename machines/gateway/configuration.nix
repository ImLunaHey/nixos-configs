{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ./killdeer.nix ];

  networking.hostName = "gateway";
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  time.timeZone = "Europe/London";

  # Preserve the provider's cloud-init networking and recovery user.
  users.users.luna = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ./admin.pub ];
  };
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    max-jobs = 1;
    cores = 1;
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  # Leave space for Nix evaluation on the 1 GB Micro VM.
  zramSwap = { enable = true; memoryPercent = 100; };
  swapDevices = [{ device = "/swapfile"; size = 1024; }];
  services.journald.extraConfig = "SystemMaxUse=100M";
  environment.systemPackages = with pkgs; [ git curl vim ];

  # Keep the original install version when upgrading the OS.
  system.stateVersion = "25.11";
}
