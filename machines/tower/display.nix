{ pkgs, ... }:
let
  collector = pkgs.callPackage ../gateway/packages/hardware-telemetry { };
  kiosk = pkgs.writeShellScript "tower-dashboard-kiosk" ''
    until ${pkgs.curl}/bin/curl --silent --fail http://127.0.0.1:8099/ >/dev/null; do
      sleep 1
    done
    exec ${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.chromium}/bin/chromium \
      --kiosk --no-first-run --no-default-browser-check \
      --disable-session-crashed-bubble --disable-infobars \
      --disable-background-networking --disable-component-update \
      --disable-gpu --ozone-platform=wayland \
      --password-store=basic --user-data-dir=/var/lib/tower-dashboard/chromium \
      http://127.0.0.1:8099/
  '';
in
{
  boot.kernelParams = [ "consoleblank=0" ];
  fonts.packages = [ pkgs.inter ];
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/tower-display"
  '';

  users.groups.tower-dashboard = { };
  users.users.tower-dashboard = {
    isSystemUser = true;
    group = "tower-dashboard";
    extraGroups = [ "video" "render" ];
    home = "/var/lib/tower-dashboard";
    createHome = true;
    # A user manager/bus is required when NixOS reloads this active session.
    linger = true;
  };

  # A local-only, read-only metrics endpoint; no extra firewall ports.
  systemd.services.tower-dashboard = {
    description = "Tower hardware dashboard metrics";
    wantedBy = [ "multi-user.target" ];
    environment = {
      METRICS_NAME = "tower";
      METRICS_INTERFACE = "enp7s0";
      NVIDIA_SMI = "/run/current-system/sw/bin/nvidia-smi";
      DASHBOARD_PEERS = builtins.toJSON {
        lake = "http://10.0.0.46:8099/api/metrics";
        nova = "http://10.0.0.178:8099/api/metrics";
        gateway = "http://10.0.0.46:8099/api/peers/gateway";
        pulsar = "http://100.117.220.119:8099/api/metrics";
        comet = "http://100.120.5.114:8099/api/metrics";
        gilbert = "";
        void = "";
      };
      DASHBOARD_HTML = "${./dashboard/index.html}";
    };
    serviceConfig = {
      User = "tower-dashboard";
      Group = "tower-dashboard";
      ExecStart = "${collector}/bin/hardware-telemetry";
      Restart = "always";
      RestartSec = "2s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  # Cage supplies a single fullscreen Wayland window, with no desktop shell.
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;
  services.cage = {
    enable = true;
    user = "tower-dashboard";
    program = kiosk;
    restartIfChanged = true;
    # Allow switching to a login VT, and hide the unused pointer on this passive display.
    extraArguments = [ "-s" "-d" ];
    environment = {
      WLR_LIBINPUT_NO_DEVICES = "1";
      # The monitor is attached to NVIDIA; avoid selecting the unused iGPU.
      WLR_DRM_DEVICES = "/dev/dri/tower-display";
      # Render this small UI on the CPU, preserving VRAM for inference.
      WLR_RENDERER = "pixman";
    };
  };
  systemd.services.cage-tty1 = {
    after = [ "tower-dashboard.service" ];
    wants = [ "tower-dashboard.service" ];
    restartTriggers = [ ./dashboard/index.html ];
    serviceConfig = {
      Restart = "always";
      RestartSec = "3s";
    };
  };
}
