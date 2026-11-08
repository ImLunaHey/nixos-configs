{ ... }:
{
  # Keep Lake's movies and shows separate from Void's music and YouTube mount.
  fileSystems."/mnt/movies" = {
    device = "lake.localdomain:/mnt/storage/media/movies";
    fsType = "nfs";
    options = [ "ro" "vers=4.2" "proto=tcp" "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/shows" = {
    device = "lake.localdomain:/mnt/storage/media/shows";
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
