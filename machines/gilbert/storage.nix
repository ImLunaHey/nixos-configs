{ ... }:
{
  fileSystems."/mnt/rips" = {
    device = "lake:/mnt/storage/void/rips";
    fsType = "nfs";
    options = [ "vers=4.2" "proto=tcp" "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

}
