{ ... }:
{
  services.samba = {
    enable = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "void";
        "security" = "user";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      media = {
        path = "/mnt/storage/media";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
      };
      rips = {
        path = "/mnt/storage/rips";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
      };
      games = {
        path = "/mnt/storage/games";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
      };
    };
  };

  # SMB discovery for macOS
  services.samba-wsdd = {
    enable = true;
    interface = "enp3s0";
  };
}
