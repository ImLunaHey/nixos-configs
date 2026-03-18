{ ... }:
{
  imports = [ ../../modules/rustic-backup.nix ];

  services.rustic-backup = {
    enable = true;
    repoName = "gilbert";
    onCalendar = "02:30";
    paths = [ "/var/lib" "/srv/minecraft" ];
  };
}
