{ ... }:
{
  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-uuid/1bb7848d-3034-4f3d-87ef-5e53036e71e4";
    fsType = "ext4";
    options = [ "defaults" ];
  };

  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/media/completed nova(rw,sync,no_subtree_check,no_root_squash) lunas-macbook-pro(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
    '';
  };
}