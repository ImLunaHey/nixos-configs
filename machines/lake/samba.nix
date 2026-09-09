{ config, pkgs, ... }:
let
  share = path: {
    inherit path;
    browseable = "yes";
    "read only" = "no";
    "guest ok" = "no";
    "valid users" = "luna";
    "force user" = "root";
  };
in
{
  systemd.tmpfiles.rules = map (name: "d /mnt/storage/${name} 0755 root root -") [
    "media"
    "files"
    "photos"
    "backups"
    "games"
    "rips"
  ];

  systemd.services.lake-timemachine-dataset = {
    description = "Create the Lake Time Machine dataset";
    after = [ "zfs-import-storage.service" ];
    before = [ "samba-smbd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ! ${pkgs.zfs}/bin/zfs list -H storage/timemachine >/dev/null 2>&1; then
        ${pkgs.zfs}/bin/zfs create \
          -o mountpoint=/mnt/storage/timemachine \
          storage/timemachine
      fi

      ${pkgs.zfs}/bin/zfs set quota=500G storage/timemachine
    '';
  };

  systemd.services.samba-setup-users = {
    description = "Configure Samba user accounts";
    after = [ "sops-install-secrets.service" ];
    before = [ "samba-smbd.service" ];
    wantedBy = [ "samba-smbd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "samba-setup-users" ''
        PASSWORD=$(cat ${config.sops.secrets.samba_password.path})
        printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | \
          ${pkgs.samba}/bin/smbpasswd -a -s luna
      '';
    };
  };

  services.samba = {
    enable = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "lake";
        security = "user";
        "map to guest" = "never";
        "veto files" = "/._*/.DS_Store/";
        "delete veto files" = "yes";
      };
      media = share "/mnt/storage/media";
      files = share "/mnt/storage/files";
      photos = share "/mnt/storage/photos";
      backups = share "/mnt/storage/backups";
      games = share "/mnt/storage/games";
      rips = share "/mnt/storage/rips";
      timemachine = (share "/mnt/storage/timemachine") // {
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = "500G";
      };
    };
  };

  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      userServices = true;
    };
  };

  services.samba-wsdd = {
    enable = true;
    interface = "enp100s0f1np1";
  };

  networking.firewall.interfaces.enp100s0f1np1 = {
    allowedTCPPorts = [ 139 445 5357 ];
    allowedUDPPorts = [ 137 138 3702 5353 ];
  };
}
