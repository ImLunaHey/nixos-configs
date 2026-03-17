{ config, pkgs, ... }:
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
    "d /var/lib/gotify            0755 100000 100000 -"
    "d /var/lib/igotify           0755 100000 100000 -"
    "d /var/lib/romm-db           0755 100000 100000 -"
    "d /var/lib/romm/resources   0755 100000 100000 -"
    "d /var/lib/romm/redis-data  0755 100000 100000 -"
    "d /var/lib/romm/assets      0755 100000 100000 -"
    "d /var/lib/romm/config      0755 100000 100000 -"
    "d /var/lib/rustfs/data      0755 100000 100000 -"
    "d /var/lib/rustfs/logs      0755 100000 100000 -"
  ];

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
        ];
        extraOptions = [
          "--device=/dev/dri:/dev/dri"
          "--group-add=video"
        ];
      };
      pihole = {
        image = "pihole/pihole:latest";
        ports = [
          "192.168.0.10:53:53/tcp"
          "192.168.0.10:53:53/udp"
          "100.106.184.73:53:53/tcp"
          "100.106.184.73:53:53/udp"
          "127.0.0.1:8081:80/tcp"
        ];
        environmentFiles = [ config.sops.secrets.pihole_password.path ];
        environment = {
          TZ = "Europe/London";
          FTLCONF_dns_listeningMode = "all";
          FTLCONF_dns_rateLimit_count = "0";
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
      gotify = {
        image = "gotify/server:latest";
        ports = [
          "127.0.0.1:8085:80"
        ];
        volumes = [
          "/var/lib/gotify:/app/data"
        ];
        environmentFiles = [ config.sops.secrets.gotify_env.path ];
      };
      igotify = {
        image = "ghcr.io/androidseb25/igotify-notification-assist:latest";
        extraOptions = [ "--network=host" "--userns=host" ]; # host network requires opting out of userns-remap
        volumes = [
          "/var/lib/igotify:/app/data"
        ];
        environmentFiles = [ config.sops.secrets.igotify_env.path ];
      };
      romm-db = {
        image = "mariadb:latest";
        volumes = [
          "/var/lib/romm-db:/var/lib/mysql"
        ];
        environmentFiles = [ config.sops.secrets.romm_env.path ];
        environment = {
          MARIADB_DATABASE = "romm";
          MARIADB_USER = "romm-user";
        };
        extraOptions = [ "--network=romm-net" ];
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