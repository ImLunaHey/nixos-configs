{ config, pkgs, ... }:
{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
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
          "/mnt/media/tv:/media/tv:ro"
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
        extraOptions = [ "--network=host" ];
        volumes = [
          "/var/lib/uptime-kuma:/app/data"
        ];
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
        };
        cmd = [ "/data" ];
      };
    };
  };
}