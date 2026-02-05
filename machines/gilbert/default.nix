{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname
  networking.hostName = "gilbert";
  networking.networkmanager.enable = true;

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

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 8080 ];  # SSH, ARM web UI
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
        volumes = [
          "/mnt/media/config:/etc/arm/config"
          "/mnt/media/logs:/home/arm/logs"
          "/mnt/media/completed:/home/arm/media"
        ];
        extraOptions = [
          "--privileged"  # Needed for optical drive access
        ];
      };
    };
  };

  system.stateVersion = "24.05";
}
