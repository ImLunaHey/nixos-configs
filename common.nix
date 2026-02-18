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
}
