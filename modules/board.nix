{ config, lib, pkgs, ... }:
let
  cfg = config.services.agent-board;
  board = pkgs.callPackage ../packages/board { };
  bridge = pkgs.callPackage ../packages/board-bridge { };
  host = "${cfg.tailnetHostname}:${toString cfg.httpsPort}";
  localUrl = "http://127.0.0.1:${toString cfg.port}/api/board";
  common = {
    User = "board";
    Group = "board";
    UMask = "0077";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    Restart = "on-failure";
    RestartSec = 5;
  };
in {
  options.services.agent-board = {
    enable = lib.mkEnableOption "private Board for coding agents";
    tailnetHostname = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption { type = lib.types.port; default = 4100; };
    httpsPort = lib.mkOption { type = lib.types.port; default = 4101; };
    allowedUsers = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      description = "Tailscale login names allowed to use this private Board.";
    };
    routesFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime JSON file with named channel/webhookUrl routes; never put bearer URLs in the Nix store.";
    };
    backupDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/storage/backups/board";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.board = { };
    users.users.board = { isSystemUser = true; group = "board"; home = "/var/lib/board"; };
    environment.systemPackages = [ board ];

    systemd.services.agent-board = {
      description = "Board API and inspector";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = { HOME = "/var/lib/board"; XDG_CONFIG_HOME = "/var/lib/board/config"; };
      postStart = ''
        export BOARD_URL=${lib.escapeShellArg localUrl}
        ready=false
        for attempt in $(seq 1 30); do
          if ${board}/bin/board whoami >/dev/null 2>&1; then ready=true; break; fi
          sleep 1
        done
        $ready
        ${pkgs.nodejs_24}/bin/node ${./board-bootstrap.mjs} ${board}/bin/board ${lib.escapeShellArgs cfg.allowedUsers}
      '';
      serviceConfig = common // {
        StateDirectory = "board";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/board";
        ExecStart = "${board}/bin/board serve --dir /var/lib/board/data --port ${toString cfg.port} --tailscale ${host} --no-open";
        # vb serve's owner token expires after 30 days; refresh it safely first.
        RuntimeMaxSec = "21d";
        Restart = "always";
      };
    };

    # Foreground serve belongs to this service and disappears when stopped.
    # Only this dedicated port is configured; existing Serve/Funnel ports stay intact.
    systemd.services.agent-board-proxy = {
      description = "Private Tailscale HTTPS for Board";
      wantedBy = [ "multi-user.target" ];
      after = [ "agent-board.service" "tailscale-autoauth.service" ];
      # Keep the proxy alive through Board's token-refresh/service restarts.
      wants = [ "agent-board.service" "tailscale-autoauth.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.httpsPort} http://127.0.0.1:${toString cfg.port}";
        Restart = "always";
        RestartSec = 5;
      };
    };

    systemd.services.board-t3-bridge = lib.mkIf (cfg.routesFile != null) {
      description = "Deliver opted-in Board replies to T3 Code";
      wantedBy = [ "multi-user.target" ];
      after = [ "agent-board.service" "network-online.target" ];
      wants = [ "agent-board.service" "network-online.target" ];
      environment = {
        BOARD_URL = localUrl;
        XDG_CONFIG_HOME = "/var/lib/board/config";
        BOARD_ROUTES_FILE = "%d/routes.json";
      };
      serviceConfig = common // {
        StateDirectory = "board-bridge";
        StateDirectoryMode = "0700";
        LoadCredential = [ "routes.json:${cfg.routesFile}" ];
        ExecStart = "${bridge}/bin/board-bridge";
        ReadOnlyPaths = [ "/var/lib/board/config" ];
      };
    };

    systemd.services.agent-board-backup = {
      description = "Daily consistent Board database and attachment backup";
      unitConfig.RequiresMountsFor = [ cfg.backupDirectory ];
      serviceConfig = { Type = "oneshot"; UMask = "0077"; };
      path = [ pkgs.coreutils pkgs.findutils pkgs.sqlite pkgs.rsync ];
      script = ''
        set -euo pipefail
        destination=${lib.escapeShellArg cfg.backupDirectory}
        install -d -m 0700 "$destination"
        snapshot="$destination/$(date -u +%Y-%m-%dT%H-%M-%SZ)"
        install -d -m 0700 "$snapshot"
        # SQLite's online backup includes committed WAL data. Copy attachments
        # afterwards so every attachment referenced by this snapshot is present.
        sqlite3 /var/lib/board/data/local.db ".backup '$snapshot/local.db'"
        if [ -d /var/lib/board/data/local ]; then
          rsync -a /var/lib/board/data/local "$snapshot/"
        fi
        if [ -d /var/lib/board-bridge ]; then
          rsync -a /var/lib/board-bridge "$snapshot/"
        fi
        find "$destination" -mindepth 1 -maxdepth 1 -type d -name '20*T*Z' -mtime +7 -exec rm -rf -- {} +
      '';
    };
    systemd.timers.agent-board-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "15m"; };
    };
  };
}
