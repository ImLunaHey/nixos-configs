{ pkgs, ... }:
{
  # Movies and shows are stored on Lake; Nova mounts these exports for Jellyfin and Watchstate.
  # SMB clients use the existing media share's movies and shows directories.
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/storage/media/movies 10.0.0.0/24(ro,sync,no_subtree_check,root_squash)
      /mnt/storage/media/shows 10.0.0.0/24(ro,sync,no_subtree_check,root_squash)
    '';
  };

  # Imports may preserve restrictive modes (e.g. rsync -a). Keep media readable
  # by remapped container users without changing ownership or write permissions.
  systemd.services.lake-media-permissions = {
    description = "Ensure shared media is readable";
    after = [ "zfs-mount.service" "systemd-tmpfiles-setup.service" ];
    requires = [ "zfs-mount.service" ];
    before = [ "nfs-server.service" "samba-smbd.service" ];
    unitConfig = {
      RequiresMountsFor = [ "/mnt/storage/media" ];
      ConditionPathIsMountPoint = "/mnt/storage";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.findutils}/bin/find /mnt/storage/media -xdev -type d ! -perm -0555 \
        -exec ${pkgs.coreutils}/bin/chmod a+rx -- {} +
      ${pkgs.findutils}/bin/find /mnt/storage/media -xdev -type f ! -perm -0444 \
        -exec ${pkgs.coreutils}/bin/chmod a+r -- {} +
    '';
  };

  systemd.timers.lake-media-permissions = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitInactiveSec = "5min";
    };
  };

  systemd.services.samba-smbd = {
    requires = [ "lake-media-permissions.service" ];
    after = [ "lake-media-permissions.service" ];
  };

  # Export only the mounted pool, never a directory on the root filesystem.
  systemd.services.nfs-server = {
    after = [ "zfs-mount.service" "lake-media-permissions.service" ];
    requires = [ "zfs-mount.service" "lake-media-permissions.service" ];
    unitConfig = {
      RequiresMountsFor = [ "/mnt/storage" ];
      ConditionPathIsMountPoint = "/mnt/storage";
    };
  };

  # Nova uses NFSv4 over TCP; no rpcbind/mountd ports are needed on the LAN.
  networking.firewall.interfaces.enp100s0f1np1.allowedTCPPorts = [ 2049 ];

  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TA25178W";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
