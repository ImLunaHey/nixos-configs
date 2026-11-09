{ pkgs, ... }:
{
  # Refuse public onboarding until the operator allows their IP at runtime.
  # Empty this file and reload Caddy once both initial admins are registered.
  systemd.services.gateway-bootstrap = {
    before = [ "caddy.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      install -d -m 0755 /var/lib/gateway-bootstrap
      if [ ! -e /var/lib/gateway-bootstrap/access.caddy ]; then
        printf '%s\n' '@bootstrapDenied not remote_ip 127.0.0.1 ::1' \
          'respond @bootstrapDenied "Initial setup is restricted" 403' \
          > /var/lib/gateway-bootstrap/access.caddy
        chmod 0644 /var/lib/gateway-bootstrap/access.caddy
      fi
    '';
    path = [ pkgs.coreutils ];
  };
  systemd.services.caddy = {
    requires = [ "gateway-bootstrap.service" ];
    after = [ "gateway-bootstrap.service" ];
  };
  services.caddy = {
    enable = true;
    email = "xo@wvvw.me";
    # Caddy 2.11.7's server-wide read-idle guard overrides route timeouts.
    # Disable it here and restore it for ordinary HTTP requests below, so
    # authenticated, idle NetBird gRPC streams are not reset every minute.
    globalConfig = ''
      servers {
        timeouts {
          read_body_idle -1s
        }
      }
    '';
    virtualHosts."flaked.org".extraConfig = ''
      timeouts {
        read_timeout 1m
      }
      root * ${./site}
      encode zstd gzip
      header {
        Alt-Svc "clear"
        Strict-Transport-Security "max-age=31536000"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "no-referrer"
        Content-Security-Policy "default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        Permissions-Policy "camera=(), microphone=(), geolocation=()"
      }
      # Keep the service document outside the public site's filesystem root.
      handle /oauth2/* {
        header Content-Security-Policy "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
        header Cache-Control "no-store"
        reverse_proxy 127.0.0.1:4180
      }
      @services path /services /services/
      handle @services {
        route {
          forward_auth 127.0.0.1:4180 {
            uri /oauth2/auth
            @unauthenticated status 401
            handle_response @unauthenticated {
              redir /oauth2/start?rd=%2Fservices 302
            }
          }
          root * ${./portal}
          rewrite * /services.html
          header Cache-Control "no-store"
          file_server
        }
      }
      handle {
        file_server
      }
    '';
    virtualHosts."netbird.flaked.org".extraConfig = ''
      import /var/lib/gateway-bootstrap/access.caddy
      @ordinaryHTTP not header Content-Type application/grpc*
      timeouts @ordinaryHTTP {
        read_timeout 1m
      }
      @grpc header Content-Type application/grpc*
      reverse_proxy @grpc h2c://127.0.0.1:8081
      @backend path /relay* /ws-proxy/* /api/* /oauth2/*
      reverse_proxy @backend 127.0.0.1:8081
      reverse_proxy /* 127.0.0.1:8080
    '';
    virtualHosts."id.flaked.org".extraConfig = ''
      timeouts {
        read_timeout 1m
      }
      import /var/lib/gateway-bootstrap/access.caddy
      reverse_proxy 127.0.0.1:1411
    '';
    virtualHosts."romm.flaked.org".extraConfig = ''
      timeouts {
        read_timeout 1m
      }
      header Alt-Svc "clear"
      header Strict-Transport-Security "max-age=31536000"
      header X-Content-Type-Options "nosniff"
      header Referrer-Policy "same-origin"
      reverse_proxy https://100.66.196.73:9444 {
        header_up Host romm.flaked.org
        transport http {
          tls_server_name romm.flaked.org
        }
      }
    '';
    virtualHosts."jellyfin.flaked.org".extraConfig = ''
      timeouts {
        read_timeout 1m
      }
      # Public ingress exposes TCP/443, so do not advertise unavailable QUIC.
      header Alt-Svc "clear"
      header Strict-Transport-Security "max-age=31536000"
      header X-Content-Type-Options "nosniff"
      header Referrer-Policy "same-origin"
      reverse_proxy https://100.66.196.73:9443 {
        header_up Host jellyfin.flaked.org
        transport http {
          tls_server_name jellyfin.flaked.org
        }
      }
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
