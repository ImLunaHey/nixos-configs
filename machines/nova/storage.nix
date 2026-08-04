{ ... }:
{
  fileSystems."/mnt/media" = {
    device = "void:/mnt/storage/media";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/games" = {
    device = "void:/mnt/storage/games";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/photos" = {
    device = "void:/mnt/storage/photos";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

}
