{ ... }:
{
  # Keep movies separate from Void's media mount (shows, music, and YouTube).
  fileSystems."/mnt/movies" = {
    device = "lake.localdomain:/mnt/storage/media/movies";
    fsType = "nfs";
    options = [ "ro" "vers=4.2" "proto=tcp" "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/media" = {
    device = "void.localdomain:/mnt/storage/media";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/games" = {
    device = "void.localdomain:/mnt/storage/games";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/photos" = {
    device = "void.localdomain:/mnt/storage/photos";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

}
