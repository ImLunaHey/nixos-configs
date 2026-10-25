#!/usr/bin/env bash
# One-time, explicit migration from the repository's SOPS file into OpenBao.
# Existing SOPS consumers remain active until a later cutover.

set -euo pipefail
umask 077

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this migration as root on Lake." >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
sops_file="$repo_root/secrets/secrets.yaml"
bootstrap_dir=/var/lib/openbao-bootstrap
init_file="$bootstrap_dir/init.json"
approle_dir="$bootstrap_dir/approles"

export BAO_ADDR=${BAO_ADDR:-https://127.0.0.1:8200}
export BAO_CACERT=${BAO_CACERT:-$bootstrap_dir/tls/ca.crt}

for command in bao jq sops; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -r "$sops_file" ]] || { echo "Cannot read $sops_file" >&2; exit 1; }
[[ -r "$init_file" ]] || {
  echo "Initialize OpenBao with 'sudo openbao-init' first." >&2
  exit 1
}

export BAO_TOKEN
BAO_TOKEN=$(jq -er '.root_token' "$init_file")

if ! bao secrets list -format=json | jq -e 'has("secret/")' >/dev/null; then
  bao secrets enable -path=secret kv-v2 >/dev/null
fi

if ! bao auth list -format=json | jq -e 'has("approle/")' >/dev/null; then
  bao auth enable approle >/dev/null
fi

read_secret() {
  local name=$1
  sops --decrypt --extract "[\"$name\"]" --output-type json "$sops_file" \
    | jq --join-output --raw-output '.'
}

write_workload_secrets() {
  local host=$1
  local workload=$2
  shift 2
  local operation="put"
  local secret

  for secret in "$@"; do
    read_secret "$secret" \
      | bao kv "$operation" -mount=secret "workloads/$host/$workload" "$secret=-" >/dev/null
    operation="patch"
  done
}

configure_workload_role() {
  local host=$1
  local workload=$2
  local policy="varlock-$host-$workload"
  local credentials="$approle_dir/$host/$workload.env"

  bao policy write "$policy" - >/dev/null <<EOF
path "secret/data/workloads/$host/$workload" {
  capabilities = ["read"]
}
EOF

  bao write "auth/approle/role/$policy" \
    token_policies="$policy" \
    token_type=service \
    token_period=1h \
    token_num_uses=0 \
    secret_id_ttl=0 \
    secret_id_num_uses=0 >/dev/null

  if [[ ! -e "$credentials" ]]; then
    local role_id secret_id
    install -d -m 0700 "$approle_dir/$host"
    role_id=$(bao read -field=role_id "auth/approle/role/$policy/role-id")
    secret_id=$(bao write -f -field=secret_id "auth/approle/role/$policy/secret-id")
    {
      printf 'VAULT_ROLE_ID=%q\n' "$role_id"
      printf 'VAULT_SECRET_ID=%q\n' "$secret_id"
    } > "$credentials"
  fi
}

install -d -m 0700 "$approle_dir"

provision_workload() {
  local host=$1
  local workload=$2
  shift 2
  write_workload_secrets "$host" "$workload" "$@"
  configure_workload_role "$host" "$workload"
}

# Lake workloads
provision_workload lake anvil anvil_auth_secret
provision_workload lake harmonia harmonia_signing_key
provision_workload lake homelab-agent homelab_agent_secret
provision_workload lake lake-health-monitor brrr_token
provision_workload lake nixos-upgrade brrr_token
provision_workload lake samba samba_password
provision_workload lake smartd brrr_token
provision_workload lake t3code lumen_t3code_private_key
provision_workload lake tailscale-autoauth tailscale_oauth

# Nova workloads
provision_workload nova caddy cloudflare_api_token
provision_workload nova cloudflare-dns-sync cloudflare_api_token
provision_workload nova homelab-agent homelab_agent_secret
provision_workload nova homelab-agent-services homelab_agent_secret uptime_kuma_password
provision_workload nova immich immich_env
provision_workload nova matrix-synapse matrix_registration_secret
provision_workload nova nixos-upgrade brrr_token
provision_workload nova pihole pihole_password
provision_workload nova romm romm_env
provision_workload nova rustfs rustfs_env
provision_workload nova rustic-backup rustic_password
provision_workload nova tailscale-autoauth tailscale_oauth
provision_workload nova uptime-kuma-sync uptime_kuma_password

# Gilbert workloads
provision_workload gilbert arm makemkv_key omdb_api_key
provision_workload gilbert homelab-agent homelab_agent_secret
provision_workload gilbert minecraft rcon_password
provision_workload gilbert nixos-upgrade brrr_token
provision_workload gilbert rustic-backup rustic_password
provision_workload gilbert tailscale-autoauth tailscale_oauth

# Void workloads
provision_workload void homelab-agent homelab_agent_secret
provision_workload void nixos-upgrade brrr_token
provision_workload void samba samba_password
provision_workload void smartd brrr_token
provision_workload void tailscale-autoauth tailscale_oauth

echo "Migration complete. Per-workload AppRole files are in $approle_dir/<host>."
echo "Copy only the matching workload file and CA certificate to each service over an authenticated channel."
echo "SOPS remains active; do not remove it until every consumer has been tested."
