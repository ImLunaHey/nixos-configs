{ config, pkgs, ... }:
{
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
      storage = {
        path = "/mnt/storage";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "luna";
        "force user" = "root";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    interface = "enp100s0f1np1";
  };

  networking.firewall.interfaces.enp100s0f1np1 = {
    allowedTCPPorts = [ 139 445 5357 ];
    allowedUDPPorts = [ 137 138 3702 ];
  };
}
