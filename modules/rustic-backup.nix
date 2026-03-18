{ config, pkgs, lib, ... }:
let
  cfg = config.services.rustic-backup;
in
{
  options.services.rustic-backup = {
    enable = lib.mkEnableOption "rustic backup to void";

    repoName = lib.mkOption {
      type = lib.types.str;
      description = "Subdirectory name under /mnt/backups for this host's repository.";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "02:00";
      description = "Systemd OnCalendar expression for when to run the backup.";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/var/lib" ];
      description = "Paths to include in the backup.";
    };

    preBackupScript = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell commands to run before the backup (e.g. database dumps).";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems."/mnt/backups" = {
      device = "192.168.0.12:/mnt/storage/backups";
      fsType = "nfs";
      options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
    };

    systemd.tmpfiles.rules = [ "d /mnt/backups 0755 root root -" ];

    systemd.services.rustic-backup = {
      description = "Rustic backup to void";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "rustic-backup" ''
          set -e
          REPO="/mnt/backups/${cfg.repoName}"
          PASSWORD_FILE="${config.sops.secrets.rustic_password.path}"

          mkdir -p "$REPO"

          ${lib.optionalString (cfg.preBackupScript != "") cfg.preBackupScript}

          # Init repo if not already initialised
          [ -f "$REPO/config" ] || ${pkgs.rustic}/bin/rustic -r "$REPO" --password-file "$PASSWORD_FILE" init

          # Backup configured paths
          ${pkgs.rustic}/bin/rustic -r "$REPO" --password-file "$PASSWORD_FILE" backup ${lib.escapeShellArgs cfg.paths}

          # Keep 7 daily, 4 weekly, 6 monthly snapshots and prune the rest
          ${pkgs.rustic}/bin/rustic -r "$REPO" --password-file "$PASSWORD_FILE" forget \
            --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
        '';
        User = "root";
      };
    };

    systemd.timers.rustic-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
      };
    };
  };
}
