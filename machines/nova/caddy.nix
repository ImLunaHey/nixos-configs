{ config, pkgs, ... }:
let
  privateDNS = import ../../infrastructure/netbird-dns.nix;
  jellyfinProxy = ''
    encode zstd gzip
    # UDP/443 is not exposed by the private access policy. Clear cached QUIC
    # advertisements instead of making mobile clients try an unreachable port.
    header Alt-Svc "clear"
    handle /flaked-assets/forest.jpg {
      root * ${../../infrastructure/jellyfin-assets}
      rewrite * /forest.jpg
      header Cache-Control "public, max-age=86400"
      file_server
    }
    ${builtins.readFile ../../infrastructure/jellyfin-proxy.caddy}
  '';
in
{
  sops.secrets.cloudflare_api_token = {};

  services.caddy = {
    enable = true;
    globalConfig = ''
      servers {
        trusted_proxies static 100.66.248.2/32
        trusted_proxies_strict
      }
    '';
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-QSiwKqKvSxhksWBF4/MlBOpyXba5xOQ2sRwA0R7399E=";
    };
    virtualHosts."matrix.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73 ${privateDNS.novaIPv4}
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:8008
      '';
    };
    virtualHosts."jellyfin.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73 ${privateDNS.novaIPv4}
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        ${jellyfinProxy}
      '';
    };
    # A separate listener prevents the VPS from reaching Nova's other sites.
    virtualHosts."jellyfin.flaked.org:9443" = {
      extraConfig = ''
        bind ${privateDNS.novaIPv4}
        # The standard HTTPS listener declares this hostname's DNS-01 policy.
        # Reuse its certificate instead of creating a duplicate policy.
        ${jellyfinProxy}
      '';
    };
    virtualHosts."pihole.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73 ${privateDNS.novaIPv4}
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
        bind 100.106.184.73 ${privateDNS.novaIPv4}
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:3001
      '';
    };
    virtualHosts."s3.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73 ${privateDNS.novaIPv4}
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:9000
      '';
    };
    virtualHosts."romm.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73 ${privateDNS.novaIPv4}
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:8083
      '';
    };
    virtualHosts."immich.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73 ${privateDNS.novaIPv4}
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:2283
      '';
    };
    virtualHosts."watchstate.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73 ${privateDNS.novaIPv4}
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        reverse_proxy 127.0.0.1:8087
      '';
    };
    virtualHosts."s3-console.flaked.org" = {
      extraConfig = ''
        bind 100.106.184.73 ${privateDNS.novaIPv4}
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        redir / /rustfs/console/ 302
        reverse_proxy 127.0.0.1:9001
      '';
    };
  };

  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 80 443 9443 ];

  services.cloudflare-dns.recordIPs."jellyfin.flaked.org" = "23.150.68.231";
  services.cloudflare-dns.recordIPs."flaked.org" = "23.150.68.231";

  systemd.services.caddy = {
    after = [ "tailscaled.service" "tailscale-autoauth.service" "netbird.service" ];
    wants = [ "tailscaled.service" "tailscale-autoauth.service" "netbird.service" ];
    serviceConfig = {
      EnvironmentFile = config.sops.secrets.cloudflare_api_token.path;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
