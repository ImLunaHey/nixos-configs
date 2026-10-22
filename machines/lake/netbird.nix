{ pkgs, ... }:
let
  domain = "netbird.flaked.org";
  lakeAddress = "10.0.0.46";
  dataRoot = "/mnt/storage/netbird";
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
        listenAddress: ":80"
        exposedAddress: "https://${domain}:443"
        stunPorts:
          - 3478
        metricsPort: 9090
        healthcheckAddress: ":9000"
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
            - "10.77.0.1/32"
          trustedPeers:
            - "10.77.0.1/32"

        store:
          engine: "sqlite"
          encryptionKey: "$datastore_encryption"
      EOF
    '';
  };
in
{
  # Run the client alongside Tailscale until every peer and route has moved.
  services.netbird = {
    useRoutingFeatures = "client";

    clients.default = {
      name = "netbird";
      interface = "wt0";
      port = 51820;
      hardened = true;
      config = {
        ManagementURL = "https://${domain}:443";
        AdminURL = "https://${domain}:443";
      };
    };
  };

  # The control plane and its encrypted SQLite store live on Lake. DigitalOcean
  # terminates public TLS and proxies these private ports over an independent
  # WireGuard tunnel; it does not hold NetBird's control-plane state.
  virtualisation.oci-containers.containers = {
    netbird-server = {
      image = "netbirdio/netbird-server:0.81.3@sha256:541ecef7e98a66b17411d44e9d4dcfdb65913415f39b3b944b8e7e748f997f1d";
      ports = [
        "${lakeAddress}:8081:80/tcp"
        "${lakeAddress}:3478:3478/udp"
      ];
      volumes = [
        "${serverData}:/var/lib/netbird"
        "${configFile}:/etc/netbird/config.yaml:ro"
      ];
      cmd = [ "--config" "/etc/netbird/config.yaml" ];
      extraOptions = [
        "--log-opt=max-size=500m"
        "--log-opt=max-file=2"
      ];
    };

    netbird-dashboard = {
      image = "netbirdio/dashboard:v2.95.0@sha256:3d6adfee19dd8d34d795af51daee69d27d2081d2076a5a304cfdd14acc67d6f4";
      ports = [ "${lakeAddress}:8080:80/tcp" ];
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
      extraOptions = [
        "--log-opt=max-size=500m"
        "--log-opt=max-file=2"
      ];
    };
  };

  systemd.services = {
    lake-netbird-dataset = {
      description = "Create the Lake NetBird dataset";
      after = [ "zfs-import-storage.service" ];
      before = [
        "netbird-control-plane-init.service"
        "docker-netbird-server.service"
        "docker-netbird-dashboard.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if ! ${pkgs.zfs}/bin/zfs list -H storage/netbird >/dev/null 2>&1; then
          ${pkgs.zfs}/bin/zfs create \
            -o mountpoint=${dataRoot} \
            storage/netbird
        fi

        ${pkgs.coreutils}/bin/install -d -m 0700 ${dataRoot}
      '';
    };

    netbird-control-plane-init = {
      description = "Initialise Lake's NetBird control-plane configuration";
      requires = [ "lake-netbird-dataset.service" ];
      after = [ "lake-netbird-dataset.service" ];
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

    docker-netbird-dashboard = {
      requires = [ "lake-netbird-dataset.service" ];
      after = [ "lake-netbird-dataset.service" ];
    };
  };

  networking.firewall = {
    trustedInterfaces = [ "wt0" ];
    interfaces.wg-do = {
      allowedTCPPorts = [ 8080 8081 ];
      allowedUDPPorts = [ 3478 ];
    };
  };

  users.users.luna.extraGroups = [ "netbird" ];
}
