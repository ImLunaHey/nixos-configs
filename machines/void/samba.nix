{ config, pkgs, ... }:
{
  # Set up luna's Samba password from secret on each boot
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
        "workgroup" = "WORKGROUP";
        "server string" = "void";
        "security" = "user";
        "guest account" = "nobody";
        "map to guest" = "bad user";
        # macOS writes AppleDouble (._*) sidecars and .DS_Store files to
        # any non-native filesystem. Veto them so Samba refuses to serve
        # or store them, and clean up any that already exist when their
        # parent directory is touched.
        "veto files" = "/._*/.DS_Store/";
        "delete veto files" = "yes";
      };
      media = {
        path = "/mnt/storage/media";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "write list" = "luna";
        "force user" = "root";
      };
      rips = {
        path = "/mnt/storage/rips";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "write list" = "luna";
        "force user" = "root";
      };
      games = {
        path = "/mnt/storage/games";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "write list" = "luna";
        "force user" = "root";
      };
      files = {
        path = "/mnt/storage/files";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "write list" = "luna";
        "force user" = "luna";
      };
    };
  };

  # SMB discovery for macOS
  services.samba-wsdd = {
    enable = true;
    interface = "enp3s0";
  };
}
