{ pkgs, ... }:
let
  lanAddress = "10.0.0.46";
  cacheDataset = "storage/lancache";
  cacheRoot = "/mnt/storage/lancache";
in
{
  virtualisation.docker.enable = true;
  virtualisation.oci-containers = {
    backend = "docker";
    containers.lancache = {
      image = "lancachenet/monolithic:latest";
      ports = [
        "${lanAddress}:80:80/tcp"
        "${lanAddress}:443:443/tcp"
      ];
      volumes = [
        "${cacheRoot}/cache:/data/cache"
        "${cacheRoot}/logs:/data/logs"
      ];
      environment = {
        CACHE_DISK_SIZE = "480g";
        CACHE_MEM_SIZE = "500m";
        UPSTREAM_DNS = "1.1.1.1 1.0.0.1";
        TZ = "Europe/London";
      };
    };
  };

  systemd.services.lake-lancache-dataset = {
    description = "Create the Lake Lancache dataset";
    after = [ "zfs-import-storage.service" ];
    before = [ "docker-lancache.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ! ${pkgs.zfs}/bin/zfs list -H ${cacheDataset} >/dev/null 2>&1; then
        ${pkgs.zfs}/bin/zfs create \
          -o mountpoint=${cacheRoot} \
          ${cacheDataset}
      fi

      ${pkgs.zfs}/bin/zfs set quota=500G ${cacheDataset}
      ${pkgs.coreutils}/bin/install -d -m 0755 \
        ${cacheRoot}/cache \
        ${cacheRoot}/logs
    '';
  };

  systemd.services.docker-lancache = {
    requires = [ "lake-lancache-dataset.service" ];
    after = [ "lake-lancache-dataset.service" ];
  };

  networking.firewall.interfaces.enp100s0f1np1.allowedTCPPorts = [ 80 443 ];
}
