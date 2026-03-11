{ config, pkgs, ... }:

{
  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # Timezone
  time.timeZone = "Europe/London";

  # Locale
  i18n.defaultLocale = "en_GB.UTF-8";

  # Basic packages
  environment.systemPackages = with pkgs; [
    nano
    tree
    git
    btop
    wget
    curl
  ];

  # Tailscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets.tailscale_key.path;
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
    listenAddresses = [
      { addr = "0.0.0.0"; port = 22; }
      { addr = "[::]"; port = 22; }
    ];
  };

  # Import SSH keys from GitHub
  users.users.root.openssh.authorizedKeys.keyFiles = [
    (builtins.fetchurl {
      url = "https://github.com/ImLunaHey.keys";
      sha256 = "1j5g3jxalsgdi42a4na3pvdbhdmmvlkpdqjhfw2b80g4hbas6n4f";
    })
  ];

  # Notify Gotify only when the system actually changed
  systemd.services.nixos-upgrade = {
    preStart = ''
      readlink /run/current-system > /tmp/nixos-pre-upgrade-system
    '';
    postStart = ''
      pre=$(cat /tmp/nixos-pre-upgrade-system 2>/dev/null)
      post=$(readlink /run/current-system)
      if [ "$pre" != "$post" ]; then
        ${pkgs.curl}/bin/curl -sf \
          -F "title=NixOS Upgraded" \
          -F "message=${config.networking.hostName} has been upgraded" \
          -F "priority=5" \
          "https://gotify.flaked.org/message?token=$(cat ${config.sops.secrets.gotify_upgrade_token.path})" \
          || true
      fi
      rm -f /tmp/nixos-pre-upgrade-system
    '';
  };

  # Auto-upgrade: poll GitHub every 15 minutes and rebuild if anything changed
  system.autoUpgrade = {
    enable = true;
    flake = "github:imlunahey/nixos-configs";
    dates = "*:0/15";           # every 15 minutes
    randomizedDelaySec = "5min"; # stagger nova and gilbert by up to 5 minutes
    allowReboot = true;
  };
}
