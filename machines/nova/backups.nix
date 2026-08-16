{ pkgs, ... }:
{
  imports = [ ../../modules/rustic-backup.nix ];

  services.rustic-backup = {
    enable = true;
    repoName = "nova";
    onCalendar = "02:00";
    paths = [ "/var/lib" "/var/backups" ];
    preBackupScript = ''
      # Dump PostgreSQL (Matrix Synapse) — raw data files are unsafe to copy live
      mkdir -p /var/backups/postgresql
      ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql}/bin/pg_dumpall \
        > /var/backups/postgresql/dump.sql

      # Dump MariaDB (ROMM) — raw InnoDB files are unsafe to copy live
      dump_dir=/var/backups/mariadb
      ${pkgs.coreutils}/bin/mkdir -p "$dump_dir"
      dump_tmp=$(${pkgs.coreutils}/bin/mktemp "$dump_dir/dump.sql.tmp.XXXXXX")
      trap '${pkgs.coreutils}/bin/rm -f "$dump_tmp"' EXIT
      ${pkgs.docker}/bin/docker exec romm-db \
        sh -c 'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --all-databases' \
        > "$dump_tmp"
      ${pkgs.coreutils}/bin/chmod 0600 "$dump_tmp"
      ${pkgs.coreutils}/bin/mv "$dump_tmp" "$dump_dir/dump.sql"
      trap - EXIT
    '';
  };
}
