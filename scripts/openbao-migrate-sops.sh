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

write_host_secrets() {
  local host=$1
  shift
  local operation="put"
  local secret

  for secret in "$@"; do
    read_secret "$secret" \
      | bao kv "$operation" -mount=secret "hosts/$host" "$secret=-" >/dev/null
    operation="patch"
  done
}

configure_host_role() {
  local host=$1
  local policy="varlock-$host"
  local credentials="$approle_dir/$host.env"

  bao policy write "$policy" - >/dev/null <<EOF
path "secret/data/hosts/$host" {
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
    role_id=$(bao read -field=role_id "auth/approle/role/$policy/role-id")
    secret_id=$(bao write -f -field=secret_id "auth/approle/role/$policy/secret-id")
    {
      printf 'VAULT_ROLE_ID=%q\n' "$role_id"
      printf 'VAULT_SECRET_ID=%q\n' "$secret_id"
    } > "$credentials"
  fi
}

install -d -m 0700 "$approle_dir"

write_host_secrets lake \
  anvil_auth_secret brrr_token harmonia_signing_key homelab_agent_secret \
  lumen_t3code_private_key samba_password tailscale_oauth
write_host_secrets nova \
  brrr_token cloudflare_api_token homelab_agent_secret immich_env \
  matrix_registration_secret pihole_password romm_env rustfs_env \
  rustic_password tailscale_oauth uptime_kuma_password
write_host_secrets gilbert \
  brrr_token homelab_agent_secret makemkv_key omdb_api_key rcon_password \
  rustic_password tailscale_oauth
write_host_secrets void \
  brrr_token homelab_agent_secret samba_password tailscale_oauth

for host in lake nova gilbert void; do
  configure_host_role "$host"
done

echo "Migration complete. Per-host AppRole files are in $approle_dir."
echo "Copy each file and the CA certificate to its host over an authenticated channel."
echo "SOPS remains active; do not remove it until every consumer has been tested."
