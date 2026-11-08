{ pkgs, ... }:
let
  dataRoot = "/mnt/storage/pocket-id";
in
{
  # Public TLS is terminated on DigitalOcean, over the independent wg-do link.
  virtualisation.oci-containers.containers.pocket-id = {
    image = "ghcr.io/pocket-id/pocket-id:v2.19.2@sha256:3ee23895d6a3adb5dd5de801a4fd31fc31b960e6dfbea9b5200e33cf477695eb";
    ports = [ "10.0.0.46:1411:1411/tcp" ];
    volumes = [
      "${dataRoot}/data:/app/data"
      "${dataRoot}/encryption-key:/run/secrets/encryption-key:ro"
    ];
    environment = {
      APP_URL = "https://id.flaked.org";
      TRUST_PROXY = "10.77.0.1/32";
      ENCRYPTION_KEY_FILE = "/run/secrets/encryption-key";
      PUID = "1000";
      PGID = "1000";
      ANALYTICS_DISABLED = "true";
      VERSION_CHECK_DISABLED = "true";
    };
    extraOptions = [
      "--log-opt=max-size=500m"
      "--log-opt=max-file=2"
    ];
  };

  systemd.services.lake-pocket-id-init = {
    description = "Prepare Lake's Pocket ID dataset and encryption key";
    after = [ "zfs-import-storage.service" ];
    before = [ "docker-pocket-id.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    path = with pkgs; [ coreutils openssl zfs util-linux ];
    script = ''
      if ! zfs list -H storage/pocket-id >/dev/null 2>&1; then
        zfs create -o mountpoint=${dataRoot} storage/pocket-id
      fi
      # Refuse to initialise identity data on the root filesystem.
      test "$(zfs get -H -o value mountpoint storage/pocket-id)" = "${dataRoot}"
      if [ "$(zfs get -H -o value mounted storage/pocket-id)" != yes ]; then
        zfs mount storage/pocket-id
      fi
      mountpoint -q ${dataRoot}
      chmod 0700 ${dataRoot}
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
    requires = [ "lake-pocket-id-init.service" ];
    after = [ "lake-pocket-id-init.service" ];
  };

  networking.firewall.interfaces.wg-do.allowedTCPPorts = [ 1411 ];
}
