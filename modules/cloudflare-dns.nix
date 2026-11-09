{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cloudflare-dns;

  # Internal listeners with explicit ports are not separate DNS records.
  records = unique ((filter (name: builtins.match "[A-Za-z0-9.-]+" name != null)
    (attrNames config.services.caddy.virtualHosts)) ++ attrNames cfg.recordIPs);

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

    # Extra records are explicitly owned; never replace unrelated mail records.
    upsert_static_record() {
      local payload="$1" name record_type existing count id
      name=$(printf '%s' "$payload" | ${pkgs.jq}/bin/jq -r .name)
      record_type=$(printf '%s' "$payload" | ${pkgs.jq}/bin/jq -r .type)
      existing=$(${pkgs.curl}/bin/curl -sf --get \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        --data-urlencode "name=$name" --data-urlencode "type=$record_type" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN")
      printf '%s' "$existing" | ${pkgs.jq}/bin/jq -e '.success == true' >/dev/null
      count=$(printf '%s' "$existing" | ${pkgs.jq}/bin/jq '.result | length')
      if [ "$count" = 0 ]; then
        echo "Creating $record_type record: $name"
        ${pkgs.curl}/bin/curl -sf -X POST \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
          -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
          -H "Content-Type: application/json" -d "$payload" \
          | ${pkgs.jq}/bin/jq -e '.success == true'
      elif [ "$count" = 1 ] && printf '%s' "$existing" | ${pkgs.jq}/bin/jq -e \
        --argjson wanted "$payload" '.result[0] | .content == $wanted.content and (.priority // null) == ($wanted.priority // null)' >/dev/null; then
        echo "Unchanged $record_type record: $name"
      elif [ "$count" = 1 ] && printf '%s' "$existing" | ${pkgs.jq}/bin/jq -e '.result[0].comment == "nixos:static"' >/dev/null; then
        id=$(printf '%s' "$existing" | ${pkgs.jq}/bin/jq -r '.result[0].id')
        echo "Updating $record_type record: $name"
        ${pkgs.curl}/bin/curl -sf -X PATCH \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$id" \
          -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
          -H "Content-Type: application/json" -d "$payload" \
          | ${pkgs.jq}/bin/jq -e '.success == true'
      else
        echo "Refusing to replace unmanaged or multiple $record_type records: $name" >&2
        return 1
      fi
    }
    ${concatMapStringsSep "\n" (record: "upsert_static_record " + escapeShellArg (builtins.toJSON (
      (removeAttrs record [ "priority" ])
      // optionalAttrs (record.priority != null) { inherit (record) priority; }
      // { ttl = 1; comment = "nixos:static"; }
    ))) cfg.staticRecords}
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
      description = "Explicit A records and per-vhost IP overrides, including sites hosted on the public gateway.";
    };
    staticRecords = mkOption {
      default = [];
      description = "Explicit mail/DNS verification records. Conflicting unmanaged records cause failure; no records are deleted.";
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          type = mkOption { type = types.enum [ "TXT" "MX" "CNAME" ]; };
          content = mkOption { type = types.str; };
          priority = mkOption { type = types.nullOr types.ints.unsigned; default = null; };
        };
      });
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
