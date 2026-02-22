{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.uptime-kuma-sync;
  
  # Derive monitors from Caddy virtual hosts
  caddyMonitors = mapAttrsToList (name: _: {
    inherit name;
    url = "https://${name}";
    type = "http";
  }) config.services.caddy.virtualHosts;

  monitorsJson = builtins.toJSON caddyMonitors;

  syncScript = pkgs.writeShellScript "uptime-kuma-sync" ''
    API_KEY=$(cat ${config.sops.secrets.uptime_kuma_api_key.path})
    BASE_URL="http://127.0.0.1:3001"

    # Get existing monitors
    EXISTING=$(${pkgs.curl}/bin/curl -s -H "Authorization: Bearer $API_KEY" \
      "$BASE_URL/api/monitors")

    # Sync monitors from Nix config
    echo '${monitorsJson}' | ${pkgs.jq}/bin/jq -c '.[]' | while read monitor; do
      NAME=$(echo $monitor | ${pkgs.jq}/bin/jq -r '.name')
      URL=$(echo $monitor | ${pkgs.jq}/bin/jq -r '.url')
      
      # Check if monitor already exists
      EXISTS=$(echo $EXISTING | ${pkgs.jq}/bin/jq -r ".[] | select(.name == \"$NAME\") | .id")
      
      if [ -z "$EXISTS" ]; then
        echo "Adding monitor: $NAME"
        ${pkgs.curl}/bin/curl -s -X POST \
          -H "Authorization: Bearer $API_KEY" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"$NAME\",\"url\":\"$URL\",\"type\":\"http\"}" \
          "$BASE_URL/api/monitors"
      fi
    done
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