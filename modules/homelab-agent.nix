{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.homelab-agent;

  # uptime-kuma-api at runtime needs `requests`, which nixpkgs doesn't
  # propagate as a runtime dep — without it the script fails immediately
  # with `ModuleNotFoundError: No module named 'requests'`.
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.uptime-kuma-api ps.requests ]);

  hostScript = pkgs.writeShellScript "homelab-agent-host" ''
    set -eu
    secret=$(cat "$CREDENTIALS_DIRECTORY/secret")
    host="${config.networking.hostName}"
    role=${escapeShellArg cfg.role}
    nixos_release="${config.system.nixos.release}"

    uptime_secs=$(${pkgs.coreutils}/bin/cut -d. -f1 /proc/uptime)
    mem_total_kb=$(${pkgs.gawk}/bin/awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    mem_avail_kb=$(${pkgs.gawk}/bin/awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    cpu_model=$(${pkgs.gawk}/bin/awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)
    cpu_cores=$(${pkgs.coreutils}/bin/nproc)
    load1=$(${pkgs.coreutils}/bin/cut -d' ' -f1 /proc/loadavg)
    disk_total_kb=$(${pkgs.coreutils}/bin/df -P / | ${pkgs.gawk}/bin/awk 'NR==2 {print $2}')
    disk_used_kb=$(${pkgs.coreutils}/bin/df -P / | ${pkgs.gawk}/bin/awk 'NR==2 {print $3}')

    # ZFS pools — only present on hosts with zfs (void). systemd unit PATH
    # doesn't include /run/current-system/sw/bin, so use the absolute path
    # rather than `command -v zpool`. The existence test then naturally
    # falls back to [] on hosts without zfs installed.
    zpools='[]'
    if [ -x /run/current-system/sw/bin/zpool ]; then
      zpools=$(/run/current-system/sw/bin/zpool list -H -p -o name,size,alloc,free,health 2>/dev/null \
        | ${pkgs.gawk}/bin/awk -F'\t' 'BEGIN{printf "["} {if(NR>1)printf ","; printf "{\"name\":\"%s\",\"size_bytes\":%s,\"alloc_bytes\":%s,\"free_bytes\":%s,\"health\":\"%s\"}",$1,$2,$3,$4,$5} END{printf "]"}')
    fi

    body=$(${pkgs.jq}/bin/jq -n \
      --arg host "$host" \
      --arg role "$role" \
      --arg nixos "$nixos_release" \
      --arg cpu_model "$cpu_model" \
      --argjson cpu_cores "$cpu_cores" \
      --argjson uptime_secs "$uptime_secs" \
      --argjson mem_total_kb "$mem_total_kb" \
      --argjson mem_avail_kb "$mem_avail_kb" \
      --arg load1 "$load1" \
      --argjson disk_total_kb "$disk_total_kb" \
      --argjson disk_used_kb "$disk_used_kb" \
      --argjson zpools "$zpools" \
      '{
        kind: "host",
        host: $host,
        ts: now,
        data: {
          role: $role,
          os: ("nixos " + $nixos),
          cpu: { model: $cpu_model, cores: $cpu_cores },
          mem_kb: { total: $mem_total_kb, available: $mem_avail_kb },
          load1: ($load1 | tonumber),
          uptime_secs: $uptime_secs,
          root_kb: { total: $disk_total_kb, used: $disk_used_kb },
          zpools: $zpools
        }
      }')

    sig=$(printf '%s' "$body" | ${pkgs.openssl}/bin/openssl dgst -sha256 -hmac "$secret" -binary | ${pkgs.coreutils}/bin/base64 -w0)

    ${pkgs.curl}/bin/curl -sf --max-time 10 -X POST \
      -H 'content-type: application/json' \
      -H "x-homelab-signature: $sig" \
      --data "$body" \
      ${escapeShellArg cfg.endpoint} \
      || { echo "homelab-agent: push failed" >&2; exit 0; }
  '';

  servicesScript = pkgs.writeText "homelab-agent-services.py" ''
    import base64, hashlib, hmac, json, os, time, urllib.request
    from uptime_kuma_api import UptimeKumaApi

    secret = open(os.environ["CREDENTIALS_DIRECTORY"] + "/secret").read().strip()
    kuma_pw = open(os.environ["CREDENTIALS_DIRECTORY"] + "/kuma_password").read().strip()

    with UptimeKumaApi("${cfg.uptimeKumaUrl}") as api:
        api.login("luna", kuma_pw)
        monitors = api.get_monitors()
        # nixpkgs uptime-kuma-api exposes avg_ping (not avg_response — that
        # name was from a different version's docs).
        avg = api.avg_ping()
        uptimes = api.uptime()
        heartbeats = api.get_heartbeats()

    services = []
    for m in monitors:
        mid = m["id"]
        last = (heartbeats.get(mid) or [{}])[-1]
        s = last.get("status")
        services.append({
            "name": m["name"],
            "url": m.get("url"),
            "status": "up" if s == 1 else ("degraded" if s == 2 else "down"),
            "latency_ms": int(avg.get(mid) or 0),
            "uptime_pct": round(((uptimes.get(mid) or {}).get(24, 0) or 0) * 100, 2),
        })

    body = json.dumps({
        "kind": "services",
        "source": "${config.networking.hostName}",
        "ts": time.time(),
        "data": services,
    }, separators=(",", ":")).encode()

    sig = base64.b64encode(hmac.new(secret.encode(), body, hashlib.sha256).digest()).decode()
    # Cloudflare's WAF 403s the default `Python-urllib/*` UA as bot
    # traffic before the request reaches the worker, so we need to send
    # something benign-looking. Same agent identity as the bash script.
    req = urllib.request.Request(
        "${cfg.endpoint}",
        data=body, method="POST",
        headers={
            "content-type": "application/json",
            "x-homelab-signature": sig,
            "user-agent": "homelab-agent/1.0 (+nixos)",
        },
    )
    try:
        urllib.request.urlopen(req, timeout=10).read()
    except Exception as e:
        print(f"homelab-agent-services: push failed: {e}")
  '';
in
{
  options.services.homelab-agent = {
    enable = mkEnableOption "Push host telemetry to imlunahey.com/homelab";

    endpoint = mkOption {
      type = types.str;
      default = "https://imlunahey.com/api/homelab/ingest";
      description = "Where to POST telemetry blobs.";
    };

    interval = mkOption {
      type = types.str;
      default = "60s";
      description = "How often the timer fires (systemd OnUnitActiveSec format).";
    };

    role = mkOption {
      type = types.str;
      default = "";
      example = "media server / reverse proxy";
      description = "Free-form label shown on the homelab page for this host.";
    };

    includeUptimeKuma = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If set, additionally scrape uptime-kuma running on this host and push
        the per-service status blob. Enable on exactly one host (the one
        running uptime-kuma).
      '';
    };

    uptimeKumaUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3001";
      description = "Local uptime-kuma URL — only used when includeUptimeKuma is true.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      sops.secrets.homelab_agent_secret = {};

      systemd.services.homelab-agent = {
        description = "Push host telemetry to imlunahey.com";
        after = [ "network-online.target" "sops-install-secrets.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          LoadCredential = "secret:${config.sops.secrets.homelab_agent_secret.path}";
          ExecStart = hostScript;
        };
      };

      systemd.timers.homelab-agent = {
        description = "Run homelab-agent on a schedule";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = cfg.interval;
          Unit = "homelab-agent.service";
        };
      };
    }

    (mkIf cfg.includeUptimeKuma {
      sops.secrets.uptime_kuma_password = {};

      systemd.services.homelab-agent-services = {
        description = "Push uptime-kuma service status to imlunahey.com";
        after = [ "network-online.target" "sops-install-secrets.service" "docker-uptime-kuma.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          LoadCredential = [
            "secret:${config.sops.secrets.homelab_agent_secret.path}"
            "kuma_password:${config.sops.secrets.uptime_kuma_password.path}"
          ];
          ExecStart = "${pythonEnv}/bin/python3 ${servicesScript}";
        };
      };

      systemd.timers.homelab-agent-services = {
        description = "Run uptime-kuma scrape on a schedule";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "90s";
          OnUnitActiveSec = cfg.interval;
          Unit = "homelab-agent-services.service";
        };
      };
    })
  ]);
}
