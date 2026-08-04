{ ... }:
{
  fileSystems."/mnt/rips" = {
    device = "void:/mnt/storage/rips";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

}
