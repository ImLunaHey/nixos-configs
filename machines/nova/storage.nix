{ ... }:
{
  fileSystems."/mnt/media" = {
    device = "gilbert:/mnt/media/completed";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };
}