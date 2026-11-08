{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cloudflare-dns;

  # Internal listeners with explicit ports are not separate DNS records.
  records = filter (name: builtins.match "[A-Za-z0-9.-]+" name != null)
    (attrNames config.services.caddy.virtualHosts);

  syncScript = pkgs.writeShellScript "cloudflare-dns-sync" ''
    set -euo pipefail

    ZONE_ID=$(${pkgs.curl}/bin/curl -sf \
      "https://api.cloudflare.com/client/v4/zones?name=${cfg.zone}" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      | ${pkgs.jq}/bin/jq -r '.result[0].id')

    if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
      echo "Failed to get zone ID for ${cfg.zone}"
      exit 1
    fi

    upsert_record() {
      local name="$1" content="$2"

      local existing_id
      existing_id=$(${pkgs.curl}/bin/curl -sf \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$name&type=A" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        | ${pkgs.jq}/bin/jq -r '.result[0].id // empty')

      local payload="{\"type\":\"A\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":false}"

      if [ -z "$existing_id" ]; then
        echo "Creating A record: $name -> $content"
        ${pkgs.curl}/bin/curl -sf -X POST \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
          -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$payload" | ${pkgs.jq}/bin/jq -e '.success == true'
      else
        echo "Updating A record: $name -> $content"
        ${pkgs.curl}/bin/curl -sf -X PATCH \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$existing_id" \
          -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$payload" | ${pkgs.jq}/bin/jq -e '.success == true'
      fi
    }

    ${concatMapStringsSep "\n" (name: ''upsert_record ${escapeShellArg name} ${escapeShellArg (cfg.recordIPs.${name} or cfg.ip)}'') records}
  '';
in
{
  options.services.cloudflare-dns = {
    enable = mkEnableOption "Cloudflare DNS sync";

    zone = mkOption {
      type = types.str;
      description = "Cloudflare zone name (e.g. flaked.org)";
    };

    ip = mkOption {
      type = types.str;
      description = "IP address for all A records";
    };
    recordIPs = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Per-host A record overrides, such as a public gateway address.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.cloudflare-dns-sync = {
      description = "Sync Caddy vhosts to Cloudflare DNS";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = config.sops.secrets.cloudflare_api_token.path;
        ExecStart = syncScript;
      };
    };
  };
}
