{ config, pkgs, ... }:
{
  sops.secrets.cloudflare_api_token = {};

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.3" ];
      hash = "sha256-bJO2RIa6hYsoVl3y2L86EM34Dfkm2tlcEsXn2+COgzo=";
    };
    virtualHosts."nova.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy localhost:8008
      '';
    };
    virtualHosts."jellyfin.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy localhost:8096
      '';
    };
    virtualHosts."pihole.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy localhost:80
      '';
    };
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = config.sops.secrets.cloudflare_api_token.path;
}