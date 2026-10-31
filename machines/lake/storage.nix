{ ... }:
{
  # Movies are stored on Lake; Nova mounts this export for Jellyfin and Watchstate.
  # SMB clients use the existing media share's movies directory.
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/storage/media/movies 10.0.0.0/24(ro,sync,no_subtree_check,root_squash)
    '';
  };

  # Export only the mounted pool, never a directory on the root filesystem.
  systemd.services.nfs-server = {
    after = [ "zfs-mount.service" ];
    requires = [ "zfs-mount.service" ];
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
