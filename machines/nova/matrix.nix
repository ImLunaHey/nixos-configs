{ config, pkgs, ... }:
{
  sops.secrets.matrix_registration_secret = {
    owner = "matrix-synapse";
  };

  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = "nova.tail3275e2.ts.net";
      public_baseurl = "https://nova.tail3275e2.ts.net";
      listeners = [{
        port = 8008;
        bind_addresses = [ "127.0.0.1" ];
        type = "http";
        tls = false;
        x_forwarded = true;
        resources = [{
          names = [ "client" "federation" ];
          compress = false;
        }];
      }];
      registration_shared_secret_path = config.sops.secrets.matrix_registration_secret.path;
    };
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.3" ];
      hash = "sha256-bJO2RIa6hYsoVl3y2L86EM34Dfkm2tlcEsXn2+COgzo=";
    };
    environmentFile = config.sops.secrets.cloudflare_api_token.path;
    virtualHosts."nova.flaked.org" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy localhost:8008
      '';
    };
  };
}