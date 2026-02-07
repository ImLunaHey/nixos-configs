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
      intel-media-driver # iHD driver for 6th gen+ Skylake
      intel-gmmlib
    ];
  };

  systemd.services.build-arm-intel-image = {
    description = "Build ARM Docker image with Ubuntu 24.04 and Intel QuickSync support";
    wantedBy = [ "multi-user.target" ];
    before = [ "docker-arm.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
          if ! ${pkgs.docker}/bin/docker image inspect arm-intel:latest >/dev/null 2>&1; then
            cat > /tmp/Dockerfile.arm << 'EOF'
      FROM automaticrippingmachine/automatic-ripping-machine:latest

      ENV DEBIAN_FRONTEND=noninteractive
      ENV NEEDRESTART_MODE=a

      # Update all packages first
      RUN apt-get update && \
          apt-get upgrade -y && \
          apt-get dist-upgrade -y

      # Upgrade to Ubuntu 24.04
      RUN apt-get install -y ubuntu-release-upgrader-core && \
          sed -i 's/Prompt=lts/Prompt=normal/' /etc/update-manager/release-upgrades && \
          echo 'DPkg::options { "--force-confdef"; "--force-confold"; }' >> /etc/apt/apt.conf.d/local && \
          do-release-upgrade -f DistUpgradeViewNonInteractive

      # Restore custom udev that gets deleted during Ubuntu upgrade
      RUN cp /opt/arm/scripts/docker/custom_udev /etc/init.d/udev && \
          chmod +x /etc/init.d/udev

      # Install MakeMKV from source since the latest version in Ubuntu 24.04 is too old
      RUN cd /tmp && \
          wget https://www.makemkv.com/download/makemkv-bin-1.18.3.tar.gz && \
          wget https://www.makemkv.com/download/makemkv-oss-1.18.3.tar.gz && \
          tar xzf makemkv-bin-1.18.3.tar.gz && \
          tar xzf makemkv-oss-1.18.3.tar.gz && \
          apt-get update && \
          apt-get install -y build-essential pkg-config libc6-dev libssl-dev libexpat1-dev libavcodec-dev libgl1-mesa-dev qtbase5-dev zlib1g-dev && \
          cd makemkv-oss-1.18.3 && ./configure && make && make install && \
          cd ../makemkv-bin-1.18.3 && mkdir -p tmp && touch tmp/eula_accepted && make && make install && \
          mv /usr/local/bin/makemkvcon /usr/local/bin/makemkvcon.old && \
          mv /usr/local/lib/libmakemkv.so.1 /usr/local/lib/libmakemkv.so.1.old && \
          mv /usr/local/lib/libdriveio.so.0 /usr/local/lib/libdriveio.so.0.old

      # Reinstall ARM Python dependencies
      RUN pip3 install --break-system-packages --ignore-installed \
          bcrypt requests argparse colorama flake8 waitress \
          flask flask-cors flask-login flask-migrate flask-sqlalchemy flask-wtf \
          apprise alembic sqlalchemy psutil pydvdid python-magic pyudev pyyaml \
          xmltodict eyed3 musicbrainzngs discid prettytable werkzeug wtforms \
          netifaces

      # Install Intel drivers, MFX libraries, HandBrake, and dependencies
      RUN apt-get update && \
          apt-get install -y \
          intel-media-va-driver-non-free \
          libmfx1 libmfx-dev \
          handbrake-cli \
          libvpx9 libmp3lame0 libopus0 libnuma1 \
          && cd /tmp && \
          wget http://archive.ubuntu.com/ubuntu/pool/universe/x/x264/libx264-163_0.163.3060+git5db6aa6-2build1_amd64.deb && \
          dpkg -i libx264-163_0.163.3060+git5db6aa6-2build1_amd64.deb && \
          rm -rf /var/lib/apt/lists/* && \
          mv /usr/local/bin/HandBrakeCLI /usr/local/bin/HandBrakeCLI.old && \
          ln -s /usr/bin/HandBrakeCLI /usr/local/bin/HandBrakeCLI

      ENV LIBVA_DRIVER_NAME=iHD
      ENV LIBVA_DRI_DEVICE=/dev/dri/renderD129
      EXPOSE 8080
      CMD ["/sbin/my_init"]
      WORKDIR /home/arm
      EOF
            
            ${pkgs.docker}/bin/docker build --no-cache -t arm-intel:latest -f /tmp/Dockerfile.arm /tmp
            rm /tmp/Dockerfile.arm
          fi
    '';
  };

  # Sops configuration
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      tailscale_key = { };
      makemkv_key = { };
      omdb_api_key = { };
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
      /mnt/media/completed nova(rw,sync,no_subtree_check,no_root_squash) lunas-macbook-pro(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
    '';
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      8080
      2049
    ]; # SSH, ARM web UI, NFS
    allowedUDPPorts = [ 2049 ]; # NFS
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
      {
        addr = "0.0.0.0";
        port = 22;
      }
      {
        addr = "[::]";
        port = 22;
      }
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
    "d /mnt/media/completed/movies 0755 1000 1000 -"
    "d /mnt/media/completed/tv 0755 1000 1000 -"
    "d /mnt/media/raw 0755 1000 1000 -"
    "d /mnt/media/transcode 0755 1000 1000 -"
    "d /mnt/media/transcode/movies 0755 1000 1000 -"
    "d /mnt/media/transcode/tv 0755 1000 1000 -"
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
        image = "arm-intel:latest";
        ports = [ "8080:8080" ];
        environment = {
          LIBVA_DRIVER_NAME = "iHD";
        };
        volumes = [
          "/mnt/media/config:/etc/arm/config"
          "/mnt/media/logs:/home/arm/logs"
          "/mnt/media:/home/arm/media"
          "/mnt/media/db:/home/arm/db"
        ];
        extraOptions = [
          "--privileged"
          "--device=/dev/sr0:/dev/sr0"
          "--device=/dev/sg0:/dev/sg0"
          "--device=/dev/dri/renderD129:/dev/dri/renderD129"
          "--device=/dev/dri/card2:/dev/dri/card2"
          "--group-add=video"
        ];
      };
    };
  };

  system.stateVersion = "24.05";
}
