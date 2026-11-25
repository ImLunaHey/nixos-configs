{ config, pkgs, ... }:
let
  peers = (import ../../infrastructure/netbird-access.nix).peers;
  root = "/mnt/storage/itsaplan";
  dataset = "storage/itsaplan";
  compose = "${pkgs.docker-compose}/bin/docker-compose --project-name itsaplan --env-file ${config.sops.secrets.itsaplan_env.path} --file ${./itsaplan-compose.yaml}";
  proxyConfig = pkgs.writeText "itsaplan.Caddyfile" ''
    {
      admin off
      auto_https off
      servers {
        trusted_proxies static ${peers.nova.ip}/32
        trusted_proxies_strict
      }
    }
    http://:4200 {
      bind 127.0.0.1 ${peers.lake.ip}
      @denied not remote_ip 127.0.0.1 ${peers.nova.ip}
      respond @denied "Forbidden" 403
      handle_path /api/* {
        reverse_proxy 127.0.0.1:4202 {
          header_up X-Forwarded-For {client_ip}
        }
      }
      @discovery path /.well-known/oauth-authorization-server* /.well-known/oauth-protected-resource* /.well-known/openid-configuration*
      handle @discovery {
        reverse_proxy 127.0.0.1:4202 {
          header_up X-Forwarded-For {client_ip}
        }
      }
      handle {
        reverse_proxy 127.0.0.1:4203 {
          header_up X-Forwarded-For {client_ip}
        }
      }
    }
  '';
in
{
  sops.secrets.itsaplan_env = {
    sopsFile = ../../secrets/itsaplan.env;
    format = "binary";
    restartUnits = [ "itsaplan.service" ];
  };

  virtualisation.docker.enable = true;

  # Docker may auto-restart containers before the Compose unit starts at boot.
  # Ensure the bind-backed volumes can never resolve to an unmounted directory.
  systemd.services.docker = {
    requires = [ "itsaplan-storage.service" ];
    after = [ "itsaplan-storage.service" ];
  };

  systemd.services.itsaplan-storage = {
    description = "Prepare It's a Plan persistent storage";
    wantedBy = [ "multi-user.target" ];
    after = [ "zfs-import-storage.service" ];
    before = [ "itsaplan.service" ];
    unitConfig.RequiresMountsFor = [ "/mnt/storage" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.zfs pkgs.coreutils ];
    script = ''
      if ! zfs list -H ${dataset} >/dev/null 2>&1; then
        zfs create -o mountpoint=${root} ${dataset}
      fi
      test "$(zfs get -H -o value mountpoint ${dataset})" = ${root}
      test "$(zfs get -H -o value mounted ${dataset})" = yes
      chmod 0700 ${root}
      install -d -m 0700 ${root}/postgres ${root}/attachments ${root}/db-backups
    '';
  };

  systemd.services.itsaplan = {
    description = "It's a Plan Community container stack";
    wantedBy = [ "multi-user.target" ];
    requires = [ "docker.service" "itsaplan-storage.service" ];
    after = [ "docker.service" "itsaplan-storage.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ root ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "15min";
      TimeoutStopSec = "3min";
      UMask = "0077";
      # The shared lock prevents a switch from racing the backup's stop/start.
      ExecStart = "${pkgs.util-linux}/bin/flock /run/itsaplan.lock ${compose} up --detach --wait --wait-timeout 300 --remove-orphans";
      ExecStopPost = "${pkgs.util-linux}/bin/flock /run/itsaplan.lock ${compose} down --timeout 60";
    };
  };

  systemd.services.itsaplan-router = {
    description = "Local routing for It's a Plan web, API and MCP";
    wantedBy = [ "multi-user.target" ];
    after = [ "itsaplan.service" "netbird.service" ];
    wants = [ "itsaplan.service" "netbird.service" ];
    serviceConfig = {
      DynamicUser = true;
      ExecStart = "${pkgs.caddy}/bin/caddy run --config ${proxyConfig} --adapter caddyfile";
      Restart = "on-failure";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  # A brief stop gives a consistent snapshot of PostgreSQL AND attachments.
  # Local snapshots protect against upgrades/deletions, not loss of the pool.
  systemd.services.itsaplan-backup = {
    description = "Consistent It's a Plan ZFS snapshot (retain 14 days)";
    requires = [ "itsaplan.service" ];
    after = [ "itsaplan.service" ];
    unitConfig.RequiresMountsFor = [ root ];
    serviceConfig = { Type = "oneshot"; UMask = "0077"; TimeoutStartSec = "15min"; };
    path = [ pkgs.zfs pkgs.coreutils pkgs.util-linux ];
    script = ''
      exec 9>/run/itsaplan.lock
      flock 9
      trap '${compose} up --detach --wait --wait-timeout 300' EXIT
      ${compose} stop --timeout 60
      zfs snapshot ${dataset}@itsaplan-$(date -u +%Y%m%dT%H%M%SZ)
      cutoff=$(date -u -d '14 days ago' +%s)
      while IFS=$'\t' read -r name created; do
        case "$name" in
          ${dataset}@itsaplan-*)
            if [ "$created" -lt "$cutoff" ]; then zfs destroy "$name"; fi
            ;;
        esac
      done < <(zfs list -H -p -t snapshot -o name,creation -r ${dataset})
    '';
  };
  systemd.timers.itsaplan-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 04:00:00"; Persistent = true; RandomizedDelaySec = "15m"; };
  };
}
