{ pkgs, ... }:
let
  dashboardConfig = pkgs.writeText "tower-btop.conf" ''
    shown_boxes = "cpu mem net gpu0"
    update_ms = 2000
    truecolor = false
    graph_symbol = "tty"
    custom_cpu_name = "tower — Ryzen 7 9700X"
    clock_format = "%H:%M:%S"
    check_temp = true
    show_coretemp = true
    show_gpu_info = "On"
    show_disks = true
    use_fstab = true
    disks_filter = "/ /boot"
    show_io_stat = true
    net_iface = "enp7s0"
    show_battery = false
  '';
in
{
  boot.kernelParams = [ "consoleblank=0" ];

  users.groups.tower-dashboard = { };
  users.users.tower-dashboard = {
    isSystemUser = true;
    group = "tower-dashboard";
    extraGroups = [ "video" "render" ];
  };

  # Reserve the first console for the dashboard; other VTs retain login prompts.
  systemd.services."getty@tty1".enable = false;
  systemd.services.tower-display = {
    description = "Tower local hardware dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" ];
    conflicts = [ "getty@tty1.service" ];
    environment = {
      TERM = "linux";
      HOME = "/run/tower-dashboard";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };
    # Use a writable copy because btop saves settings when it exits.
    preStart = ''
      ${pkgs.coreutils}/bin/install -m 0600 ${dashboardConfig} /run/tower-dashboard/btop.conf
    '';
    serviceConfig = {
      User = "tower-dashboard";
      Group = "tower-dashboard";
      SupplementaryGroups = [ "video" "render" ];
      RuntimeDirectory = "tower-dashboard";
      RuntimeDirectoryMode = "0700";
      ExecStart = "${pkgs.btop}/bin/btop --tty --config /run/tower-dashboard/btop.conf";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "journal";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
      Restart = "always";
      RestartSec = "2s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
