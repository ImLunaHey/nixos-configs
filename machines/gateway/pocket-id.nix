{ pkgs, ... }:
let
  dataRoot = "/var/lib/pocket-id";
in
{
  # HTTP is local to the host; Caddy terminates public TLS.
  virtualisation.oci-containers.containers.pocket-id = {
    image = "ghcr.io/pocket-id/pocket-id:v2.19.2@sha256:3ee23895d6a3adb5dd5de801a4fd31fc31b960e6dfbea9b5200e33cf477695eb";
    volumes = [
      "${dataRoot}/data:/app/data"
      "${dataRoot}/encryption-key:/run/secrets/encryption-key:ro"
    ];
    environment = {
      HOST = "127.0.0.1";
      ACTORS_HOST = "127.0.0.1";
      ALLOW_INSECURE_CALLBACK_URLS = "false";
      APP_URL = "https://id.flaked.org";
      TRUST_PROXY = "127.0.0.1/32";
      ENCRYPTION_KEY_FILE = "/run/secrets/encryption-key";
      PUID = "1000";
      PGID = "1000";
      ANALYTICS_DISABLED = "true";
      VERSION_CHECK_DISABLED = "true";
    };
    extraOptions = [
      "--network=host"
    ];
  };

  systemd.services.pocket-id-init = {
    description = "Prepare Pocket ID state and encryption key";
    before = [ "docker-pocket-id.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    path = with pkgs; [ coreutils openssl ];
    script = ''
      install -d -m 0700 ${dataRoot}
      install -d -m 0700 -o 1000 -g 1000 ${dataRoot}/data
      if [ ! -s ${dataRoot}/encryption-key ]; then
        # Never replace a lost key for an existing database.
        test -z "$(ls -A ${dataRoot}/data)"
        openssl rand -base64 32 > ${dataRoot}/encryption-key.tmp
        chown 1000:1000 ${dataRoot}/encryption-key.tmp
        chmod 0400 ${dataRoot}/encryption-key.tmp
        mv ${dataRoot}/encryption-key.tmp ${dataRoot}/encryption-key
      fi
    '';
  };

  systemd.services.docker-pocket-id = {
    requires = [ "pocket-id-init.service" ];
    after = [ "pocket-id-init.service" ];
  };

}
