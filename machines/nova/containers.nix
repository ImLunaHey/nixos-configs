{ config, lib, pkgs, cache-domains, ... }:
let
  lancacheAddress = "10.0.0.46";
  lancacheDnsmasqConfig = pkgs.runCommand "lancache-steam-dnsmasq.conf" {
    nativeBuildInputs = [ pkgs.jq ];
  } ''
    cp -r ${cache-domains} source
    chmod -R u+w source
    cd source/scripts
    cat > config.json <<'EOF'
    {
      "combined_output": false,
      "ips": { "generic": "${lancacheAddress}" },
      "cache_domains": {
        "default": "disabled",
        "steam": "generic"
      }
    }
    EOF
    bash create-dnsmasq.sh
    cp output/dnsmasq/steam.conf "$out"
  '';

  # This is the source of truth for Pi-hole's subscribed blocklists. Lists added
  # through the web UI are removed on the next deployment or boot.
  piholeAdlists = [
    {
      address = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt";
      comment = "HaGeZi Multi PRO";
    }
    {
      address = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/tif.mini.txt";
      comment = "HaGeZi Threat Intelligence Feeds Mini";
    }
  ];

  escapeSql = value: lib.replaceStrings [ "'" ] [ "''" ] value;
  piholeAdlistsSql = pkgs.writeText "pihole-adlists.sql" ''
    .timeout 10000
    BEGIN IMMEDIATE;
    CREATE TEMP TABLE nix_adlists (
      address TEXT PRIMARY KEY,
      comment TEXT NOT NULL
    );
    ${lib.concatMapStringsSep "\n" (adlist: ''
      INSERT INTO nix_adlists (address, comment) VALUES (
        '${escapeSql adlist.address}',
        '${escapeSql adlist.comment}'
      );
    '') piholeAdlists}

    INSERT INTO adlist (address, enabled, comment, type)
      SELECT address, 1, comment, 0 FROM nix_adlists WHERE true
      ON CONFLICT(address, type) DO UPDATE SET
        enabled = excluded.enabled,
        comment = excluded.comment;

    DELETE FROM adlist
      WHERE type = 0
        AND address NOT IN (SELECT address FROM nix_adlists);
    COMMIT;
  '';
in
{
  # dockremap is required for Docker userns-remap — cannot be auto-created with mutableUsers = false
  users.users.dockremap = {
    isSystemUser = true;
    group = "dockremap";
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
  };
  users.groups.dockremap = {};

  # Create volume dirs owned by the remapped container UID (100000 = container root)
  # so containers can write to them on a fresh machine without manual chown
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin/config  0755 100000 100000 -"
    "d /var/lib/jellyfin/cache   0755 100000 100000 -"
    "d /var/lib/pihole/pihole    0755 100000 100000 -"
    "d /var/lib/pihole/dnsmasq   0755 100000 100000 -"
    "d /var/lib/uptime-kuma      0755 100000 100000 -"
    # MariaDB drops to uid 999; it must be able to unlink tc.log on shutdown.
    "d /var/lib/romm-db           0755 100999 100999 -"
    "d /var/lib/romm/resources   0755 100000 100000 -"
    "d /var/lib/romm/redis-data  0755 100000 100000 -"
    "d /var/lib/romm/assets      0755 100000 100000 -"
    "d /var/lib/romm/config      0755 100000 100000 -"
    "d /var/lib/rustfs/data      0755 110001 110001 -"
    "d /var/lib/rustfs/logs      0755 110001 110001 -"
    "d /var/lib/immich/postgres  0755 100000 100000 -"
    "d /var/lib/immich/ml-cache  0755 100000 100000 -"
    "d /var/lib/watchstate/config 0755 100000 100000 -"
  ];

  # RustFS now runs as uid 10001 rather than container root. Repair existing
  # volumes too: duplicate d/Z tmpfiles entries do not apply recursively.
  systemd.services.docker-rustfs.preStart = lib.mkBefore ''
    ${pkgs.coreutils}/bin/chown -R 110001:110001 /var/lib/rustfs/data /var/lib/rustfs/logs
  '';

  systemd.services.create-immich-network = {
    description = "Create immich Docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    before = [ "docker-immich-server.service" "docker-immich-machine-learning.service" "docker-immich-redis.service" "docker-immich-postgres.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "-${pkgs.docker}/bin/docker network create immich-net";
    };
  };

  # Never start Immich with an unmounted upload directory.
  systemd.services.docker-immich-server = {
    requires = [ "mnt-photos.mount" ];
    after = [ "mnt-photos.mount" ];
  };

  # Containers must not bind the empty directories beneath an unmounted NFS path.
  systemd.services.docker-jellyfin = {
    requires = [ "mnt-media.mount" "mnt-movies.mount" "mnt-shows.mount" ];
    after = [ "mnt-media.mount" "mnt-movies.mount" "mnt-shows.mount" ];
  };

  systemd.services.docker-watchstate = {
    requires = [ "mnt-media.mount" "mnt-movies.mount" "mnt-shows.mount" ];
    after = [ "mnt-media.mount" "mnt-movies.mount" "mnt-shows.mount" ];
  };

  systemd.services.docker-ytdl-sub = {
    requires = [ "mnt-media.mount" ];
    after = [ "mnt-media.mount" ];
  };

  systemd.services.docker-romm = {
    requires = [ "mnt-games.mount" ];
    after = [ "mnt-games.mount" ];
  };

  systemd.services.create-media-network = {
    description = "Create media Docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    before = [ "docker-jellyfin.service" "docker-watchstate.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "-${pkgs.docker}/bin/docker network create media-net";
    };
  };

  systemd.services.create-romm-network = {
    description = "Create romm Docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    before = [ "docker-romm.service" "docker-romm-db.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "-${pkgs.docker}/bin/docker network create romm-net";
    };
  };

  systemd.services.pihole-adlists = {
    description = "Reconcile Pi-hole adlists managed by Nix";
    after = [ "network-online.target" "docker-pihole.service" ];
    wants = [ "network-online.target" ];
    requires = [ "docker-pihole.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ piholeAdlistsSql ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for _ in {1..30}; do
        if ${pkgs.docker}/bin/docker exec pihole pihole-FTL sqlite3 \
          /etc/pihole/gravity.db "SELECT 1 FROM adlist LIMIT 1" \
          >/dev/null 2>&1; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done

      ${pkgs.docker}/bin/docker exec -i pihole pihole-FTL sqlite3 \
        /etc/pihole/gravity.db < ${piholeAdlistsSql}
      ${pkgs.docker}/bin/docker exec pihole pihole -g
    '';
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
    daemon.settings = {
      "userns-remap" = "default";
      "dns" = [ "1.1.1.1" "1.0.0.1" ]; # fallback DNS so image pulls work before Pi-hole is up
    };
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      jellyfin = {
        ports = [
          "127.0.0.1:8096:8096"
        ];
        volumes = [
          "/var/lib/jellyfin/config:/config"
          "/var/lib/jellyfin/cache:/cache"
          "/mnt/movies:/media/movies:ro"
          "/mnt/shows:/media/shows:ro"
          "/mnt/media/music:/media/music:ro"
          "/mnt/media/youtube:/media/youtube:ro"
        ];
        extraOptions = [
          "--device=/dev/dri:/dev/dri"
          "--group-add=video"
          "--network=media-net"
        ];
      };
      pihole = {
        image = "pihole/pihole:2026.10.1@sha256:30f803ad5dd60ff96cc0a63008a2e9271af481c1b0399a182192b2e91152c1f9";
        ports = [
          "53:53/tcp"
          "53:53/udp"
          "127.0.0.1:8081:80/tcp"
        ];
        environmentFiles = [ config.sops.secrets.pihole_password.path ];
        environment = {
          TZ = "Europe/London";
          FTLCONF_dns_listeningMode = "all";
          FTLCONF_dns_rateLimit_count = "0";
          FTLCONF_misc_etc_dnsmasq_d = "true";
          FTLCONF_dns_revServers =
            "true,100.64.0.0/10,100.100.100.100,tail3275e2.ts.net";
        };
        volumes = [
          "/var/lib/pihole/pihole:/etc/pihole"
          "/var/lib/pihole/dnsmasq:/etc/dnsmasq.d"
          "${lancacheDnsmasqConfig}:/etc/dnsmasq.d/99-lancache-steam.conf:ro"
        ];
      };
      uptime-kuma = {
        image = "louislam/uptime-kuma:2.5.9@sha256:e88415a90dd2f7efecdbc18de0490aff292764a3ac471531bf1d0481725591bd";
        extraOptions = [ "--network=host" "--userns=host" ]; # host network requires opting out of userns-remap
        volumes = [
          "/var/lib/uptime-kuma:/app/data"
        ];
      };
      romm-db = {
        # Keep the server version in lockstep with the on-disk data format.
        # A floating `latest` tag plus an unclean shutdown can leave tc.log
        # unreadable by the next image and prevent MariaDB crash recovery.
        image = "mariadb:12.3.3@sha256:d46e102fa8b9b72bfcdeb56f9dd538742092119dc8b11f31fe662605cd234cd9";
        volumes = [
          "/var/lib/romm-db:/var/lib/mysql"
        ];
        environmentFiles = [ config.sops.secrets.romm_env.path ];
        environment = {
          MARIADB_DATABASE = "romm";
          MARIADB_USER = "romm-user";
          MARIADB_AUTO_UPGRADE = "1";
        };
        extraOptions = [
          "--network=romm-net"
          "--stop-timeout=120"
        ];
      };
      romm = {
        image = "rommapp/romm:5.4.1@sha256:8677fb7b81b1d3db20b849e989a1dadc2a11159e51eb34a2acdcb01102274edf";
        ports = [
          "127.0.0.1:8083:8080"
        ];
        volumes = [
          "/var/lib/romm/resources:/romm/resources"
          "/var/lib/romm/redis-data:/redis-data"
          "/var/lib/romm/assets:/romm/assets"
          "/var/lib/romm/config:/romm/config"
          "/mnt/games:/romm/library"
        ];
        environmentFiles = [ config.sops.secrets.romm_env.path config.sops.secrets.romm_oidc_env.path ];
        environment = {
          ROMM_BASE_URL = "https://romm.flaked.org";
          OIDC_ENABLED = "true";
          OIDC_PROVIDER = "pocket-id";
          OIDC_SERVER_APPLICATION_URL = "https://id.flaked.org";
          OIDC_REDIRECT_URI = "https://romm.flaked.org/api/oauth/openid";
          OIDC_USERNAME_ATTRIBUTE = "preferred_username";
          OIDC_CLAIM_ROLES = "groups";
          OIDC_ROLE_ADMIN = "romm-admins";
          OIDC_ROLE_VIEWER = "romm-users";
          # Pocket ID restricts this client to explicitly enrolled RomM users.
          # New accounts inherit RomM's non-admin Viewer permission group.
          OIDC_ALLOW_REGISTRATION = "true";
          OIDC_AUTOLOGIN = "true";
          DB_HOST = "romm-db";
          DB_NAME = "romm";
          DB_USER = "romm-user";
        };
        extraOptions = [ "--network=romm-net" ];
        dependsOn = [ "romm-db" ];
      };
      immich-server = {
        image = "ghcr.io/immich-app/immich-server:v3.3.6@sha256:e1981983b1c13f6024b57d72e7ecae3342eed1581201ab09fb248932d86c593a";
        ports = [
          "127.0.0.1:2283:2283"
        ];
        volumes = [
          "/mnt/photos:/usr/src/app/upload"
          "/etc/localtime:/etc/localtime:ro"
        ];
        environmentFiles = [ config.sops.secrets.immich_env.path ];
        environment = {
          # Preserve the existing media root and database paths across v3.
          IMMICH_MEDIA_LOCATION = "/usr/src/app/upload";
          DB_HOSTNAME = "immich-postgres";
          DB_USERNAME = "immich";
          DB_DATABASE_NAME = "immich";
          REDIS_HOSTNAME = "immich-redis";
        };
        extraOptions = [ "--network=immich-net" ];
        dependsOn = [ "immich-postgres" "immich-redis" ];
      };
      immich-machine-learning = {
        image = "ghcr.io/immich-app/immich-machine-learning:v3.3.6@sha256:14367bfb374b8576ddf49abd67c5ca0190a4c7fcf6303cdad65d7f7bf1a50bc2";
        volumes = [
          "/var/lib/immich/ml-cache:/cache"
        ];
        extraOptions = [ "--network=immich-net" ];
      };
      immich-redis = {
        image = "valkey/valkey:9.1.3@sha256:3add1a336a920ea54770a001ab6feb3da5fceea96a40373a3a2cd469b815f0b7";
        extraOptions = [ "--network=immich-net" ];
      };
      immich-postgres = {
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
        volumes = [
          "/var/lib/immich/postgres:/var/lib/postgresql/data"
        ];
        environmentFiles = [ config.sops.secrets.immich_env.path ];
        environment = {
          POSTGRES_USER = "immich";
          POSTGRES_DB = "immich";
        };
        extraOptions = [ "--network=immich-net" ];
      };
      watchstate = {
        image = "ghcr.io/arabcoders/watchstate:v1.10.11@sha256:2433ee5fb699390d1b2f551d6f6735f5733586459510bd907addc610e247d519";
        user = "0:0"; # image drops to uid 1000 by default; force root so userns-remap maps to host 100000
        ports = [
          "127.0.0.1:8087:8080"
        ];
        volumes = [
          "/var/lib/watchstate/config:/config"
          "/mnt/movies:/media/movies:ro"
          "/mnt/shows:/media/shows:ro"
          "/mnt/media/music:/media/music:ro"
        ];
        environment = {
          WS_TZ = "Europe/London";
        };
        extraOptions = [ "--network=media-net" ];
      };
      rustfs = {
        image = "rustfs/rustfs:1.0.4@sha256:ed9210d6411d77ffceb70d94b964a3cb7d225983368bc25bebe01e995293dcc2";
        ports = [
          "127.0.0.1:9000:9000"
          "127.0.0.1:9001:9001"
        ];
        volumes = [
          "/var/lib/rustfs/data:/data"
          "/var/lib/rustfs/logs:/logs"
        ];
        environmentFiles = [ config.sops.secrets.rustfs_env.path ];
        environment = {
          RUSTFS_VOLUMES = "/data";
          RUSTFS_ADDRESS = "0.0.0.0:9000";
          RUSTFS_CONSOLE_ADDRESS = "0.0.0.0:9001";
          RUSTFS_CONSOLE_ENABLE = "true";
          RUSTFS_SERVER_DOMAINS = "s3.flaked.org,s3-console.flaked.org";
        };
        cmd = [ "/data" ];
      };
    };
  };
}
