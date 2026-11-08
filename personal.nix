{ config, pkgs, ... }:
{
  imports = [
    ./modules/brrr-notify.nix
    ./modules/homelab-agent.nix
    ./modules/netbird-client.nix
    ./modules/lake-cache-client.nix
  ];

  homelabBase = {
    user = {
      name = "luna";
      passwordlessSudo = true;
      authorizedKeyFiles = [(builtins.fetchurl {
        url = "https://github.com/ImLunaHey.keys";
        sha256 = "17b8ip05wyjvab7kl43ym19cv70vam05cwf4bnbin0pl3i1h1c7m";
      })];
    };
    ssh.enable = true;
    vpn.provider = "tailscale";
    autoUpgrade.enable = false;
  };

  services.homelab-agent.enable = true;

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
        echo "Tailscale already authenticated, keeping DNS on the LAN resolver"
        ${pkgs.tailscale}/bin/tailscale set --accept-dns=false
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
      ${pkgs.tailscale}/bin/tailscale up --reset --auth-key "$auth_key" --advertise-tags=tag:server --accept-dns=false
    '';
  };

}
