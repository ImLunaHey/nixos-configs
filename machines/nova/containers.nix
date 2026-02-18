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
        ports = [ "8096:8096" ];
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
          "80:80/tcp"
        ];
        environmentFiles = [ config.sops.secrets.pihole_password.path ];
        environment = {
          TZ = "Europe/London";
          FTLCONF_dns_listeningMode = "all";
        };
        volumes = [
          "/var/lib/pihole/pihole:/etc/pihole"
          "/var/lib/pihole/dnsmasq:/etc/dnsmasq.d"
        ];
      };
    };
  };
}