{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname
  networking.hostName = "nova";
  networking.networkmanager.enable = false;
  networking.interfaces.enp1s0.ipv4.addresses = [{
    address = "192.168.0.10";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.0.1";
  networking.nameservers = [ "1.1.1.1" ];

  # Sops configuration
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    
    secrets = {
      tailscale_key = {};
      pihole_password = {};
    };
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets.tailscale_key.path;
    extraUpFlags = [ "--accept-dns=true" "--reset" ];
  };

  # Mount NFS share from gilbert
  fileSystems."/mnt/media" = {
    device = "gilbert:/mnt/media/completed";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 8096 ];  # SSH, Pi-hole, Jellyfin
    allowedUDPPorts = [ 53 ];  # DNS
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
    listenAddresses = [
      { addr = "0.0.0.0"; port = 22; }
      { addr = "[::]"; port = 22; }
    ];
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
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # Create directories
  systemd.tmpfiles.rules = [
    "d /mnt/media 0755 root root -"
    "d /var/lib/jellyfin 0755 root root -"
    "d /var/lib/jellyfin/config 0755 root root -"
    "d /var/lib/jellyfin/cache 0755 root root -"
    "d /var/lib/pihole 0755 root root -"
    "d /var/lib/pihole/pihole 0755 root root -"
    "d /var/lib/pihole/dnsmasq 0755 root root -"
  ];

  # Containers
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
        };
        volumes = [
          "/var/lib/pihole/pihole:/etc/pihole"
          "/var/lib/pihole/dnsmasq:/etc/dnsmasq.d"
        ];
      };
    };
  };

  system.stateVersion = "24.05";
}
