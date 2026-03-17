{ ... }:
{
  # Disko declarative disk layout
  # Boot SSD + 3x 1TB data drives in RAIDZ1 (2TB usable, 1-drive fault tolerance)
  # Supports future RAIDZ expansion (OpenZFS 2.2+) by adding more drives to the vdev.
  #
  # TODO: replace device paths with stable by-id paths after install:
  #   ls /dev/disk/by-id/ | grep -v part
  disko.devices = {
    disk = {
      boot = {
        type = "disk";
        device = "/dev/disk/by-id/ata-KINGSTON_SHSS37A240G_50026B72570B9985";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
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

      data1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST1000DM003-1ER162_Z4YA3HPM";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage";
              };
            };
          };
        };
      };

      data2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD10EFRX-68PJCN0_WD-WCC4J0XU8HLZ";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage";
              };
            };
          };
        };
      };

      data3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD10EFRX-68PJCN0_WD-WCC4J1YNHNUV";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage";
              };
            };
          };
        };
      };
    };

    zpool = {
      storage = {
        type = "zpool";
        mode = "raidz"; # RAIDZ1: 2TB usable, survives 1 drive failure
        options = {
          ashift = "12"; # 4K sector alignment
        };
        rootFsOptions = {
          compression = "lz4";
          acltype = "posixacl";
          xattr = "sa";
          relatime = "on";
          "com.sun:auto-snapshot" = "false";
        };
        datasets = {
          media = {
            type = "zfs_fs";
            mountpoint = "/mnt/media";
          };
        };
      };
    };
  };

  # ZFS scrub — monthly, catches silent bit-rot
  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };

  # NFS exports
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/media 192.168.0.10(rw,sync,no_subtree_check,root_squash)
    '';
  };
}
