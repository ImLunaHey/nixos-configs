{ config, pkgs, ... }:

{
  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    allowed-users = [ "@wheel" "root" ];
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
    useRoutingFeatures = "client";
  };

  # Authenticate Tailscale using OAuth client credentials (never expire).
  # Generates a single-use non-ephemeral preauth key on first boot via the API.
  systemd.services.tailscale-autoauth = {
    description = "Tailscale authentication via OAuth";
    after = [ "tailscaled.service" "sops-install-secrets.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = config.sops.secrets.tailscale_oauth.path;
    };
    script = ''
      state=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState // "unknown"')
      if [ "$state" = "Running" ]; then
        echo "Tailscale already authenticated, skipping"
        exit 0
      fi

      token=$(${pkgs.curl}/bin/curl -sf \
        --data "client_id=$TAILSCALE_OAUTH_CLIENT_ID" \
        --data "client_secret=$TAILSCALE_OAUTH_CLIENT_SECRET" \
        --data "grant_type=client_credentials" \
        https://api.tailscale.com/api/v2/oauth/token | ${pkgs.jq}/bin/jq -r '.access_token')

      auth_key=$(${pkgs.curl}/bin/curl -sf -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":false,"preauthorized":true,"tags":["tag:server"]}}},"expirySeconds":300}' \
        https://api.tailscale.com/api/v2/tailnet/-/keys | ${pkgs.jq}/bin/jq -r '.key')

      ${pkgs.tailscale}/bin/tailscale up --reset --auth-key "$auth_key" --advertise-tags=tag:server
    '';
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    listenAddresses = [
      { addr = "0.0.0.0"; port = 22; }
      { addr = "[::]"; port = 22; }
    ];
  };

  # Only allow SSH via Tailscale
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # Users
  users.mutableUsers = false;

  users.users.root = {
    hashedPassword = "!"; # lock root account
  };

  users.users.luna = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [
      (builtins.fetchurl {
        url = "https://github.com/ImLunaHey.keys";
        sha256 = "1j5g3jxalsgdi42a4na3pvdbhdmmvlkpdqjhfw2b80g4hbas6n4f";
      })
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # Notify Gotify on upgrade success or failure
  systemd.services.nixos-upgrade = {
    preStart = ''
      readlink /nix/var/nix/profiles/system > /tmp/nixos-pre-upgrade-system
    '';
    postStart = ''
      pre=$(cat /tmp/nixos-pre-upgrade-system 2>/dev/null)
      post=$(readlink /nix/var/nix/profiles/system)
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
    serviceConfig.ExecStopPost = [
      "+${pkgs.writeShellScript "nixos-upgrade-notify-failure" ''
        if [ "$SERVICE_RESULT" != "success" ]; then
          ${pkgs.curl}/bin/curl -sf \
            -F "title=NixOS Upgrade Failed" \
            -F "message=${config.networking.hostName} failed to upgrade: $SERVICE_RESULT" \
            -F "priority=8" \
            "https://gotify.flaked.org/message?token=$(cat ${config.sops.secrets.gotify_upgrade_token.path})" \
            || true
        fi
      ''}"
    ];
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
