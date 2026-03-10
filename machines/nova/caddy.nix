{ config, pkgs, ... }:
{
  sops.secrets.cloudflare_api_token = {};

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.3" ];
      hash = "sha256-bL1cpMvDogD/pdVxGA8CAMEXazWpFDBiGBxG83SmXLA=";
    };
    virtualHosts."matrix.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:8008
      '';
    };
    virtualHosts."jellyfin.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:8096
      '';
    };
    virtualHosts."pihole.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        redir / /admin/ 301
        reverse_proxy 127.0.0.1:8081
      '';
    };
    virtualHosts."status.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:3001
      '';
    };
    virtualHosts."s3.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:9000
      '';
    };
    virtualHosts."gotify.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:8085
      '';
    };
    virtualHosts."igotify.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:8086
      '';
    };
    virtualHosts."s3-console.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:9001
      '';
    };
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = config.sops.secrets.cloudflare_api_token.path;
}