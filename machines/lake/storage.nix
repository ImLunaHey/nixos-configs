{ pkgs, ... }:
{
  # Shared storage for Nova, Gilbert and their backups. SMB uses the same paths.
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/storage/media/movies 10.0.0.0/24(ro,sync,no_subtree_check,root_squash)
      /mnt/storage/media/shows 10.0.0.0/24(ro,sync,no_subtree_check,root_squash)
      /mnt/storage/media 10.0.0.0/24(rw,sync,no_subtree_check,root_squash)
      /mnt/storage/games 10.0.0.0/24(rw,sync,no_subtree_check,root_squash)
      /mnt/storage/photos 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)
      /mnt/storage/rips gilbert(rw,sync,no_subtree_check,no_root_squash)
      /mnt/storage/backups 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash) gilbert(rw,sync,no_subtree_check,no_root_squash)
    '';
  };

  # Keep media readable and let remapped containers write photos, music and YouTube.
  systemd.services.lake-media-permissions = {
    description = "Prepare shared storage permissions";
    after = [ "zfs-mount.service" "systemd-tmpfiles-setup.service" ];
    requires = [ "zfs-mount.service" ];
    before = [ "nfs-server.service" "samba-smbd.service" ];
    unitConfig = {
      RequiresMountsFor = [ "/mnt/storage/media" "/mnt/storage/photos" ];
      ConditionPathIsMountPoint = "/mnt/storage";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      # Immich and ytdl-sub use Docker's remapped root (uid/gid 100000).
      ${pkgs.coreutils}/bin/mkdir -p /mnt/storage/photos /mnt/storage/media/music /mnt/storage/media/youtube
      ${pkgs.coreutils}/bin/chown 100000:100000 \
        /mnt/storage/photos /mnt/storage/media/music /mnt/storage/media/youtube
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
