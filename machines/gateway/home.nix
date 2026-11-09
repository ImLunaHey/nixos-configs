{ pkgs, ... }:
let
  settings = (pkgs.formats.toml {}).generate "flaked-home-oauth2.toml" {
    provider = "oidc";
    provider_display_name = "Pocket ID";
    oidc_issuer_url = "https://id.flaked.org";
    redirect_url = "https://flaked.org/oauth2/callback";
    scope = "openid profile email groups";
    code_challenge_method = "S256";
    email_domains = [ "*" ];
    allowed_groups = [ "home-users" ];
    # Accounts are administrator-provisioned and access is granted by group,
    # never by an email allowlist. Pocket ID has no email verification here.
    insecure_oidc_allow_unverified_email = true;
    insecure_oidc_skip_nonce = false;
    http_address = "127.0.0.1:4180";
    reverse_proxy = true;
    trusted_proxies = [ "127.0.0.1/32" ];
    upstreams = [ "static://202" ];
    skip_provider_button = true;
    cookie_name = "__Host-flaked_session";
    cookie_secure = true;
    cookie_httponly = true;
    cookie_samesite = "lax";
    cookie_expire = "8h";
    cookie_refresh = "5m";
    whitelist_domains = [ "flaked.org" ];
    # Callback query strings contain short-lived authorization codes.
    request_logging = false;
  };
in {
  systemd.services.flaked-home-auth = {
    description = "Pocket ID authentication for flaked home";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "docker-pocket-id.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.oauth2-proxy}/bin/oauth2-proxy --config=${settings}";
      EnvironmentFile = "/var/lib/flaked-home/oauth2.env";
      DynamicUser = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
