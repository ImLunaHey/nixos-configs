{ pkgs, ... }:
let
  # Rebuild the local Intel variant when its pinned base or recipe changes.
  armImage = "arm-intel:${builtins.hashFile "sha256" ./arm-config/Dockerfile}";
in
{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  systemd.services.build-arm-intel-image = {
    description = "Build ARM Docker image with Ubuntu 24.04 and Intel QuickSync support";
    wantedBy = [ "multi-user.target" ];
    before = [ "docker-arm.service" ];
    restartTriggers = [ ./arm-config/Dockerfile ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
          if ! ${pkgs.docker}/bin/docker image inspect ${armImage} >/dev/null 2>&1; then
            ${pkgs.docker}/bin/docker build --no-cache -t ${armImage} -f ${./arm-config/Dockerfile} /tmp
          fi
    '';
  };

  systemd.services.docker-arm = {
    requires = [ "build-arm-intel-image.service" ];
    after = [ "build-arm-intel-image.service" ];
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      arm = {
        image = "${armImage}";
        ports = [ "8080:8080" ];
        environment = {
          LIBVA_DRIVER_NAME = "iHD";
        };
        volumes = [
          "/mnt/media/config:/etc/arm/config"
          "/mnt/media/logs:/home/arm/logs"
          "/mnt/media:/home/arm/media"
          "/mnt/rips:/home/arm/media/completed"
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
}