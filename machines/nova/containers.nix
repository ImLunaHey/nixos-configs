{ config, lib, pkgs, ... }:
let
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
    "d /var/lib/romm-db           0755 100000 100000 -"
    "d /var/lib/romm/resources   0755 100000 100000 -"
    "d /var/lib/romm/redis-data  0755 100000 100000 -"
    "d /var/lib/romm/assets      0755 100000 100000 -"
    "d /var/lib/romm/config      0755 100000 100000 -"
    "d /var/lib/rustfs/data      0755 100000 100000 -"
    "d /var/lib/rustfs/logs      0755 100000 100000 -"
    "d /var/lib/immich/postgres  0755 100000 100000 -"
    "d /var/lib/immich/ml-cache  0755 100000 100000 -"
    "d /var/lib/watchstate/config 0755 100000 100000 -"
  ];

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
    requires = [ "mnt-media.mount" ];
    after = [ "mnt-media.mount" ];
  };

  systemd.services.docker-watchstate = {
    requires = [ "mnt-media.mount" ];
    after = [ "mnt-media.mount" ];
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
        image = "jellyfin/jellyfin:latest";
        ports = [
          "127.0.0.1:8096:8096"
        ];
        volumes = [
          "/var/lib/jellyfin/config:/config"
          "/var/lib/jellyfin/cache:/cache"
          "/mnt/media/movies:/media/movies:ro"
          "/mnt/media/shows:/media/shows:ro"
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
        image = "pihole/pihole:latest";
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
          FTLCONF_dns_revServers =
            "true,100.64.0.0/10,100.100.100.100,tail3275e2.ts.net";
        };
        volumes = [
          "/var/lib/pihole/pihole:/etc/pihole"
          "/var/lib/pihole/dnsmasq:/etc/dnsmasq.d"
        ];
      };
      uptime-kuma = {
        image = "louislam/uptime-kuma:latest";
        extraOptions = [ "--network=host" "--userns=host" ]; # host network requires opting out of userns-remap
        volumes = [
          "/var/lib/uptime-kuma:/app/data"
        ];
      };
      romm-db = {
        # Keep the server version in lockstep with the on-disk data format.
        # A floating `latest` tag plus an unclean shutdown can leave tc.log
        # unreadable by the next image and prevent MariaDB crash recovery.
        image = "mariadb:12.2.2@sha256:310a2b521cdf1c3c1cfd2cb468e3f0843cc0d7b06d7325b7d48e197592f5d8bd";
        volumes = [
          "/var/lib/romm-db:/var/lib/mysql"
        ];
        environmentFiles = [ config.sops.secrets.romm_env.path ];
        environment = {
          MARIADB_DATABASE = "romm";
          MARIADB_USER = "romm-user";
        };
        extraOptions = [
          "--network=romm-net"
          "--stop-timeout=120"
        ];
      };
      romm = {
        image = "rommapp/romm:latest";
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
        environmentFiles = [ config.sops.secrets.romm_env.path ];
        environment = {
          DB_HOST = "romm-db";
          DB_NAME = "romm";
          DB_USER = "romm-user";
        };
        extraOptions = [ "--network=romm-net" ];
        dependsOn = [ "romm-db" ];
      };
      immich-server = {
        image = "ghcr.io/immich-app/immich-server:release";
        ports = [
          "127.0.0.1:2283:2283"
        ];
        volumes = [
          "/mnt/photos:/usr/src/app/upload"
          "/etc/localtime:/etc/localtime:ro"
        ];
        environmentFiles = [ config.sops.secrets.immich_env.path ];
        environment = {
          DB_HOSTNAME = "immich-postgres";
          DB_USERNAME = "immich";
          DB_DATABASE_NAME = "immich";
          REDIS_HOSTNAME = "immich-redis";
        };
        extraOptions = [ "--network=immich-net" ];
        dependsOn = [ "immich-postgres" "immich-redis" ];
      };
      immich-machine-learning = {
        image = "ghcr.io/immich-app/immich-machine-learning:release";
        volumes = [
          "/var/lib/immich/ml-cache:/cache"
        ];
        extraOptions = [ "--network=immich-net" ];
      };
      immich-redis = {
        image = "redis:6.2-alpine";
        extraOptions = [ "--network=immich-net" ];
      };
      immich-postgres = {
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
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
        image = "ghcr.io/arabcoders/watchstate:latest";
        user = "0:0"; # image drops to uid 1000 by default; force root so userns-remap maps to host 100000
        ports = [
          "127.0.0.1:8087:8080"
        ];
        volumes = [
          "/var/lib/watchstate/config:/config"
          "/mnt/media/movies:/media/movies:ro"
          "/mnt/media/shows:/media/shows:ro"
          "/mnt/media/music:/media/music:ro"
        ];
        environment = {
          WS_TZ = "Europe/London";
        };
        extraOptions = [ "--network=media-net" ];
      };
      rustfs = {
        image = "rustfs/rustfs:latest";
        ports = [
          "127.0.0.1:9000:9000"
          "127.0.0.1:9001:9001"
        ];
        volumes = [
          "/var/lib/rustfs/data:/data"
          "/var/lib/rustfs/logs:/app/logs"
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
