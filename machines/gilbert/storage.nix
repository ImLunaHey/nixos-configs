{ ... }:
{
  fileSystems."/mnt/rips" = {
    device = "192.168.0.12:/mnt/storage/rips";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };
}
