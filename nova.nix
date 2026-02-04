{ config, pkgs, ... }:

{
  # Hostname
  networking.hostName = "nova";
  networking.networkmanager.enable = true;

  # Sops secrets
  sops.secrets = {
    tailscale_key = {};
    pihole_password = {};
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 8096 ];  # SSH, Pi-hole, Jellyfin
    allowedUDPPorts = [ 53 ];  # DNS
    trustedInterfaces = [ "tailscale0" ];
  };

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Intel GPU for Jellyfin transcoding
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver  # Changed from vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # Create directories
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin 0755 root root -"
    "d /var/lib/jellyfin/config 0755 root root -"
    "d /var/lib/jellyfin/cache 0755 root root -"
    "d /var/lib/pihole 0755 root root -"
    "d /var/lib/pihole/pihole 0755 root root -"
    "d /var/lib/pihole/dnsmasq 0755 root root -"
    "d /var/lib/tailscale 0755 root root -"
  ];

  # Containers
  virtualisation.oci-containers = {
    backend = "docker";
    
    containers = {
      tailscale = {
        image = "tailscale/tailscale:latest";
        hostname = "nova-tailscale";
        environmentFiles = [ config.sops.secrets.tailscale_key.path ];
        environment = {
          TS_STATE_DIR = "/var/lib/tailscale";
        };
        volumes = [
          "/var/lib/tailscale:/var/lib/tailscale"
          "/dev/net/tun:/dev/net/tun"
        ];
        extraOptions = [
          "--cap-add=NET_ADMIN"
          "--cap-add=SYS_MODULE"
        ];
      };

      jellyfin = {
        image = "jellyfin/jellyfin:latest";
        ports = [ "8096:8096" ];
        volumes = [
          "/var/lib/jellyfin/config:/config"
          "/var/lib/jellyfin/cache:/cache"
        ];
        extraOptions = [
          "--device=/dev/dri:/dev/dri"
          "--group-add=video"
          "--group-add=render"
        ];
        dependsOn = [ "tailscale" ];
      };
      
      pihole = {
        image = "pihole/pihole:latest";
        ports = [
          "53:53/tcp"
          "53:53/udp"
          "80:80/tcp"
        ];
        environmentFiles = [ config.sops.secrets.pihole_password.path ];
        environment = {
          TZ = "Europe/London";
        };
        volumes = [
          "/var/lib/pihole/pihole:/etc/pihole"
          "/var/lib/pihole/dnsmasq:/etc/dnsmasq.d"
        ];
      };

      watchtower = {
        image = "containrrr/watchtower:latest";
        volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
        environment = {
          WATCHTOWER_CLEANUP = "true";
          WATCHTOWER_INCLUDE_STOPPED = "true";
          WATCHTOWER_SCHEDULE = "0 0 4 * * *";
        };
      };
    };
  };

  system.stateVersion = "24.05";
}
