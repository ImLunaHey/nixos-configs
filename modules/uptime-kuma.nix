{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.uptime-kuma-sync;

  caddyMonitors = mapAttrsToList (name: _: {
    inherit name;
    url = "https://${name}";
    type = "http";
  }) config.services.caddy.virtualHosts;

  monitorsJson = builtins.toJSON caddyMonitors;

  pythonEnv = pkgs.python3.withPackages (ps: [ ps.uptime-kuma-api ]);

  syncScript = pkgs.writeShellScript "uptime-kuma-sync" ''
  API_KEY=$(cat ${config.sops.secrets.uptime_kuma_api_key.path})
  export API_KEY
  echo '${monitorsJson}' > /tmp/monitors.json
  ${pythonEnv}/bin/python3 ${pkgs.writeText "sync.py" ''
import json
import os
from uptime_kuma_api import UptimeKumaApi, MonitorType

with open("/tmp/monitors.json") as f:
    monitors = json.load(f)

api_key = os.environ.get("API_KEY")

with UptimeKumaApi("http://127.0.0.1:3001") as api:
    api.login_by_token(api_key)
    existing = {m["name"]: m for m in api.get_monitors()}

    for monitor in monitors:
        if monitor["name"] not in existing:
            print(f"Adding monitor: {monitor['name']}")
            api.add_monitor(
                type=MonitorType.HTTP,
                name=monitor["name"],
                url=monitor["url"],
            )
        else:
            print(f"Monitor already exists: {monitor['name']}")
  ''}
'';
in
{
  options.services.uptime-kuma-sync = {
    enable = mkEnableOption "Uptime Kuma sync";
  };

  config = mkIf cfg.enable {
    sops.secrets.uptime_kuma_api_key = {};

    systemd.services.uptime-kuma-sync = {
      description = "Sync monitors to Uptime Kuma";
      after = [ "docker-uptime-kuma.service" ];
      wants = [ "docker-uptime-kuma.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = syncScript;
      };
    };
  };
}