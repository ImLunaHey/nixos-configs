{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname
  networking.hostName = "gilbert";
  networking.networkmanager.enable = true;

  boot.kernelModules = [ "sg" ];

  # Enable Intel GPU drivers for 6th gen Skylake
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver  # iHD driver for 6th gen+ Skylake
    ];
  };

  # Sops configuration
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    
    secrets = {
      tailscale_key = {};
      makemkv_key = {};
      omdb_api_key = {};
    };
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets.tailscale_key.path;
  };

  # Mount second drive for media storage
  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-uuid/1bb7848d-3034-4f3d-87ef-5e53036e71e4";
    fsType = "ext4";
    options = [ "defaults" ];
  };

  # NFS server to share media with nova
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/media/completed nova(rw,sync,no_subtree_check,no_root_squash)
    '';
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 8080 2049 ];  # SSH, ARM web UI, NFS
    allowedUDPPorts = [ 2049 ];  # NFS
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

  # Create directories for ARM with correct ownership
  systemd.tmpfiles.rules = [
    "d /mnt/media 0755 root root -"
    "d /mnt/media/config 0755 1000 1000 -"
    "d /mnt/media/logs 0755 1000 1000 -"
    "d /mnt/media/completed 0755 1000 1000 -"
    "d /mnt/media/raw 0755 1000 1000 -"
    "d /mnt/media/transcode 0755 1000 1000 -"
    "d /mnt/media/db 0755 1000 1000 -"
  ];

  # Generate ARM config with secrets substituted
  system.activationScripts.arm-config = {
    deps = [ "setupSecrets" ];
    text = ''
      ${pkgs.gnused}/bin/sed \
        -e "s|@MAKEMKV_KEY@|$(cat ${config.sops.secrets.makemkv_key.path})|g" \
        -e "s|@OMDB_API_KEY@|$(cat ${config.sops.secrets.omdb_api_key.path})|g" \
        ${./arm-config/arm.yaml} > /mnt/media/config/arm.yaml
      chown 1000:1000 /mnt/media/config/arm.yaml
      chmod 644 /mnt/media/config/arm.yaml
    '';
  };

  # Automatic Ripping Machine container
  virtualisation.oci-containers = {
    backend = "docker";
    
    containers = {
      arm = {
        image = "automaticrippingmachine/automatic-ripping-machine:latest";
        ports = [ "8080:8080" ];
        environment = {
          LIBVA_DRIVER_NAME = "iHD";
          LIBVA_DRIVERS_PATH = "/run/opengl-driver/lib/dri";
        };
        volumes = [
          "/mnt/media/config:/etc/arm/config"
          "/mnt/media/logs:/home/arm/logs"
          "/mnt/media:/home/arm/media"
          "/mnt/media/db:/home/arm/db"
          "${pkgs.intel-media-driver}/lib/dri/iHD_drv_video.so:/usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so:ro"
        ];
        extraOptions = [
          "--privileged"
          "--device=/dev/sr0:/dev/sr0"
          "--device=/dev/sg0:/dev/sg0"
          "--device=/dev/dri/renderD129:/dev/dri/renderD129"
          "--device=/dev/dri/card2:/dev/dri/card2"
          "--group-add=video"
          "--group-add=render"
        ];
      };
    };
  };

  system.stateVersion = "24.05";
}
