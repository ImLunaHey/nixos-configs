{ pkgs, ... }:
let
  root = "/mnt/storage/void";
  shares = [ "media" "games" "photos" "rips" "backups" "files" ];
in
{
  # The verified copy lives here. Keep Lake's pre-existing shares and files intact.
  services.nfs.server.exports = ''
    ${root}/media 10.0.0.0/24(rw,sync,no_subtree_check,root_squash)
    ${root}/games 10.0.0.0/24(rw,sync,no_subtree_check,root_squash)
    ${root}/photos 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)
    ${root}/rips gilbert(rw,sync,no_subtree_check,no_root_squash)
    ${root}/backups 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash) gilbert(rw,sync,no_subtree_check,no_root_squash)
  '';

  services.samba.settings = builtins.listToAttrs (map (name: {
    name = "void-${name}";
    value = {
      path = "${root}/${name}";
      comment = "${name} migrated from Void";
      browseable = "yes";
      "read only" = "no";
      "guest ok" = "no";
      "valid users" = "luna";
      # Match Void's writer identity, including luna-owned files.
      "force user" = if name == "files" then "luna" else "root";
    };
  }) shares);

  systemd.services.lake-imported-storage = {
    description = "Check imported storage and prepare container write permissions";
    requires = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
    before = [ "nfs-server.service" "samba-smbd.service" ];
    unitConfig.RequiresMountsFor = [ "/mnt/storage" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      set -eu
      # Fail rather than silently exporting empty directories on the system SSD.
      ${pkgs.util-linux}/bin/mountpoint -q /mnt/storage
      for name in ${builtins.concatStringsSep " " shares}; do
        test -d "${root}/$name"
      done
      # Immich and ytdl-sub use Docker's remapped root (uid/gid 100000).
      test -d ${root}/media/music
      test -d ${root}/media/youtube
      ${pkgs.coreutils}/bin/chown 100000:100000 \
        ${root}/photos ${root}/media/music ${root}/media/youtube
    '';
  };

  systemd.services.nfs-server = {
    requires = [ "lake-imported-storage.service" ];
    after = [ "lake-imported-storage.service" ];
  };
  systemd.services.samba-smbd = {
    requires = [ "lake-imported-storage.service" ];
    after = [ "lake-imported-storage.service" ];
  };
}
