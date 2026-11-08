{ pkgs, ... }:
let
  domain = "netbird.flaked.org";
  dataRoot = "/var/lib/netbird-control-plane";
  serverData = "${dataRoot}/server";
  configFile = "${dataRoot}/config.yaml";

  initialiseConfig = pkgs.writeShellApplication {
    name = "netbird-control-plane-init";
    runtimeInputs = with pkgs; [ coreutils openssl ];
    text = ''
      umask 077
      install -d -m 0700 ${dataRoot} ${serverData} ${dataRoot}/secrets

      create_secret() {
        file=${dataRoot}/secrets/"$1"
        if [ ! -s "$file" ]; then
          if [ -n "$(ls -A ${serverData})" ]; then
            echo "Refusing to replace a missing NetBird secret for an existing database" >&2
            exit 1
          fi
          openssl rand -base64 32 | tr -d '\n' > "$file"
          chmod 0600 "$file"
        fi
      }

      create_secret relay-auth
      create_secret datastore-encryption
      create_secret session-cookie-encryption

      relay_auth=$(tr -d '=' < ${dataRoot}/secrets/relay-auth)
      datastore_encryption=$(<${dataRoot}/secrets/datastore-encryption)
      session_cookie_encryption=$(<${dataRoot}/secrets/session-cookie-encryption)

      install -m 0600 /dev/null ${configFile}
      cat > ${configFile} <<EOF
      server:
        listenAddress: ":8081"
        exposedAddress: "https://${domain}:443"
        stunPorts:
          - 3478
        metricsPort: 9090
        healthcheckAddress: "127.0.0.1:9000"
        logLevel: "info"
        logFile: "console"

        authSecret: "$relay_auth"
        dataDir: "/var/lib/netbird"

        auth:
          issuer: "https://${domain}/oauth2"
          signKeyRefreshEnabled: true
          sessionCookieEncryptionKey: "$session_cookie_encryption"
          dashboardRedirectURIs:
            - "https://${domain}/nb-auth"
            - "https://${domain}/nb-silent-auth"
          cliRedirectURIs:
            - "http://localhost:53000/"

        reverseProxy:
          trustedHTTPProxies:
            - "127.0.0.1/32"
          trustedPeers:
            - "127.0.0.1/32"

        store:
          engine: "sqlite"
          encryptionKey: "$datastore_encryption"
      EOF
    '';
  };
in
{
  # Host networking preserves real source addresses for STUN. This version
  # binds management on all interfaces; the host firewall keeps 8081 private.
  # Caddy terminates TLS and is the only trusted HTTP proxy.
  virtualisation.oci-containers.containers = {
    netbird-server = {
      image = "netbirdio/netbird-server:0.81.3@sha256:541ecef7e98a66b17411d44e9d4dcfdb65913415f39b3b944b8e7e748f997f1d";
      volumes = [
        "${serverData}:/var/lib/netbird"
        "${configFile}:/etc/netbird/config.yaml:ro"
      ];
      cmd = [ "--config" "/etc/netbird/config.yaml" ];
      extraOptions = [
        "--network=host"
      ];
    };

    netbird-dashboard = {
      image = "netbirdio/dashboard:v2.95.0@sha256:3d6adfee19dd8d34d795af51daee69d27d2081d2076a5a304cfdd14acc67d6f4";
      ports = [ "127.0.0.1:8080:80/tcp" ];
      environment = {
        NETBIRD_MGMT_API_ENDPOINT = "https://${domain}";
        NETBIRD_MGMT_GRPC_API_ENDPOINT = "https://${domain}";
        AUTH_AUDIENCE = "netbird-dashboard";
        AUTH_CLIENT_ID = "netbird-dashboard";
        AUTH_CLIENT_SECRET = "";
        AUTH_AUTHORITY = "https://${domain}/oauth2";
        USE_AUTH0 = "false";
        AUTH_SUPPORTED_SCOPES = "openid profile email groups";
        AUTH_REDIRECT_URI = "/nb-auth";
        AUTH_SILENT_REDIRECT_URI = "/nb-silent-auth";
        NGINX_SSL_PORT = "443";
        LETSENCRYPT_DOMAIN = "none";
      };
    };
  };

  systemd.services = {
    netbird-control-plane-init = {
      description = "Initialise the gateway's NetBird control-plane configuration";
      before = [ "docker-netbird-server.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.lib.getExe initialiseConfig;
      };
    };

    docker-netbird-server = {
      requires = [ "netbird-control-plane-init.service" ];
      after = [ "netbird-control-plane-init.service" ];
    };

  };

  networking.firewall.allowedUDPPorts = [ 3478 ];
}
