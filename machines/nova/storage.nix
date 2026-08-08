{ ... }:
{
  fileSystems."/mnt/media" = {
    device = "10.0.0.241:/mnt/storage/media";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/games" = {
    device = "10.0.0.241:/mnt/storage/games";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/photos" = {
    device = "10.0.0.241:/mnt/storage/photos";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

}
