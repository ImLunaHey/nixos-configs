{ ... }:
{
  # Lake's original movies/shows stay separate from the imported music/YouTube library.
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
    device = "lake.localdomain:/mnt/storage/void/media";
    fsType = "nfs";
    options = [ "vers=4.2" "proto=tcp" "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/games" = {
    device = "lake.localdomain:/mnt/storage/void/games";
    fsType = "nfs";
    options = [ "vers=4.2" "proto=tcp" "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  fileSystems."/mnt/photos" = {
    device = "lake.localdomain:/mnt/storage/void/photos";
    fsType = "nfs";
    options = [ "vers=4.2" "proto=tcp" "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

}
