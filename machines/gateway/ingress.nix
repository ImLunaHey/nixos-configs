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
    virtualHosts."netbird.flaked.org".extraConfig = ''
      import /var/lib/gateway-bootstrap/access.caddy
      @grpc header Content-Type application/grpc*
      reverse_proxy @grpc h2c://127.0.0.1:8081
      @backend path /relay* /ws-proxy/* /api/* /oauth2/*
      reverse_proxy @backend 127.0.0.1:8081
      reverse_proxy /* 127.0.0.1:8080
    '';
    virtualHosts."id.flaked.org".extraConfig = ''
      import /var/lib/gateway-bootstrap/access.caddy
      reverse_proxy 127.0.0.1:1411
    '';
    virtualHosts."jellyfin.flaked.org".extraConfig = ''
      header Strict-Transport-Security "max-age=31536000"
      header X-Content-Type-Options "nosniff"
      header Referrer-Policy "same-origin"
      reverse_proxy https://100.66.196.73:9443 {
        transport http {
          tls_server_name jellyfin.flaked.org
        }
      }
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
