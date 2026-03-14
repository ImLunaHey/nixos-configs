#!/usr/bin/env bash
# Generates README.md from the current repository structure.
# Run manually or automatically via the pre-commit hook.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$REPO_ROOT/README.md"

get_ip() {
  grep 'address = "' "$REPO_ROOT/machines/$1/networking.nix" 2>/dev/null \
    | head -1 \
    | sed 's/.*address = "\([^"]*\)".*/\1/'
}

get_containers() {
  local file="$REPO_ROOT/machines/$1/containers.nix"
  [[ -f "$file" ]] || return 0
  # Match container names: lines with exactly 6 spaces indent followed by an identifier and ' = {'
  grep -E '^      [a-z][a-zA-Z0-9_-]+ = \{' "$file" 2>/dev/null \
    | sed 's/^ *//' | sed 's/ = {.*//' \
    || true
}

get_key_services() {
  local machine="$1"
  local services=()

  [[ -f "$REPO_ROOT/machines/$machine/matrix.nix" ]]   && services+=("Matrix-Synapse")
  [[ -f "$REPO_ROOT/machines/$machine/caddy.nix" ]]    && services+=("Caddy")
  [[ -f "$REPO_ROOT/machines/$machine/minecraft.nix" ]] && services+=("Minecraft (ATM10)")
  [[ -f "$REPO_ROOT/machines/$machine/smartd.nix" ]]   && services+=("ZFS + SMART monitoring")

  while IFS= read -r c; do
    [[ -n "$c" ]] && services+=("\`$c\`")
  done < <(get_containers "$machine")

  local IFS=', '
  echo "${services[*]:-—}"
}

get_purpose() {
  case "$1" in
    nova)    echo "Media server, reverse proxy, Matrix homeserver" ;;
    gilbert) echo "Media ripping (ARM), Minecraft server, NFS storage" ;;
    void)    echo "NAS with ZFS RAID storage" ;;
    *)       echo "—" ;;
  esac
}

machines_table() {
  echo "| Host | IP | Purpose | Key Services |"
  echo "|------|----|---------|--------------|"
  for machine_dir in "$REPO_ROOT/machines"/*/; do
    local name ip purpose services
    name=$(basename "$machine_dir")
    ip=$(get_ip "$name")
    purpose=$(get_purpose "$name")
    services=$(get_key_services "$name")
    echo "| \`$name\` | \`$ip\` | $purpose | $services |"
  done
}

machine_sections() {
  for machine_dir in "$REPO_ROOT/machines"/*/; do
    local name
    name=$(basename "$machine_dir")

    echo "### \`$name\`"
    echo ""
    echo "**IP:** \`$(get_ip "$name")\` &nbsp; **Purpose:** $(get_purpose "$name")"
    echo ""
    echo "| File | Role |"
    echo "|------|------|"
    for f in "$machine_dir"*.nix; do
      local fname
      fname=$(basename "$f")
      case "$fname" in
        hardware-configuration.nix) echo "| \`$fname\` | Generated hardware config (do not edit) |" ;;
        hardware.nix)               echo "| \`$fname\` | GPU drivers and hardware acceleration |" ;;
        networking.nix)             echo "| \`$fname\` | Static IP, firewall, Tailscale |" ;;
        services.nix)               echo "| \`$fname\` | SOPS secret declarations |" ;;
        storage.nix)                echo "| \`$fname\` | Disk mounts and NFS |" ;;
        containers.nix)             echo "| \`$fname\` | Docker container definitions |" ;;
        caddy.nix)                  echo "| \`$fname\` | Reverse proxy virtual hosts |" ;;
        matrix.nix)                 echo "| \`$fname\` | Matrix-Synapse homeserver + PostgreSQL |" ;;
        minecraft.nix)              echo "| \`$fname\` | Minecraft server (ATM10 / NeoForge) |" ;;
        smartd.nix)                 echo "| \`$fname\` | SMART disk monitoring + notifications |" ;;
        default.nix)                echo "| \`$fname\` | Imports all machine modules |" ;;
        *)                          echo "| \`$fname\` | |" ;;
      esac
    done
    if [[ -d "$machine_dir/arm-config" ]]; then
      echo "| \`arm-config/\` | ARM app config (\`arm.yaml\`) + \`Dockerfile\` |"
    fi
    echo ""
  done
}

flake_inputs() {
  awk '
    /^  [a-zA-Z_-]+ = \{/ { name = $1 }
    /url = "/ && name != "" {
      gsub(/.*url = "/, ""); gsub(/".*/, "")
      print "| `" name "` | " $0 " |"
      name = ""
    }
  ' "$REPO_ROOT/flake.nix"
}

cat > "$README" << HEREDOC
# Luna's NixOS Configurations

Personal NixOS system configurations managed with [flakes](https://nixos.wiki/wiki/Flakes) and [sops-nix](https://github.com/Mic92/sops-nix) for encrypted secrets.

> **This file is auto-generated.** Edit \`scripts/generate-readme.sh\` to change its contents.

## Structure

\`\`\`
nixos-configs/
├── flake.nix              # Flake entry point with host definitions
├── common.nix             # Shared configuration for all hosts
├── machines/
│   ├── nova/              # Media server / reverse proxy / Matrix
│   ├── gilbert/           # Media ripping / Minecraft / NFS
│   └── void/              # NAS (ZFS RAID)
├── modules/
│   └── uptime-kuma.nix    # Custom uptime-kuma sync module
├── scripts/
│   ├── generate-readme.sh # Regenerates this file
│   ├── install-hooks.sh   # Installs git hooks
│   ├── update.sh          # Pull + nixos-rebuild on current host
│   ├── install.sh         # Bootstrap any machine via nixos-anywhere
│   └── sops.sh            # Secrets management helper
├── .githooks/
│   └── pre-commit         # Auto-regenerates README on commit
└── secrets/
    └── secrets.yaml       # Encrypted secrets (gitignored)
\`\`\`

## Machines

$(machines_table)

## Machine Details

$(machine_sections)

## Common Configuration (\`common.nix\`)

Applied to every host:

- **Nix:** flakes + nix-command enabled, auto-optimise-store
- **Timezone:** Europe/London, locale en\_GB.UTF-8
- **Packages:** nano, tree, git, btop, wget, curl
- **SSH:** password auth disabled, root login restricted; keys imported from GitHub
- **Tailscale:** enabled on all hosts with routing features
- **Auto-upgrade:** polls \`github:imlunahey/nixos-configs\` every 15 minutes, reboots if needed
- **Gotify notification:** sent when a host successfully upgrades to a new generation

## Flake Inputs

| Input | Source |
|-------|--------|
$(flake_inputs)

## Scripts

| Script | Purpose |
|--------|---------|
| \`scripts/generate-readme.sh\` | Regenerate this README from repo structure |
| \`scripts/install-hooks.sh\` | Configure git to use \`.githooks/\` |
| \`scripts/update.sh\` | \`git pull\` then \`nixos-rebuild switch\` on the current host |
| \`scripts/install.sh <machine> <ip>\` | Bootstrap any machine from a NixOS live ISO via nixos-anywhere |
| \`scripts/sops.sh <cmd>\` | list / get / set / delete / edit secrets |

## Secrets Management

Secrets are encrypted with [SOPS](https://github.com/mozilla/sops) + [age](https://github.com/FiloSottile/age).

Each machine decrypts secrets via its host SSH key (\`/etc/ssh/ssh_host_ed25519_key\`). Age keys are defined in \`.sops.yaml\`.

\`\`\`bash
# List secrets
./scripts/sops.sh list

# Get a secret
./scripts/sops.sh get tailscale_key

# Add or update a secret
./scripts/sops.sh set my_secret my_value

# Open in editor
./scripts/sops.sh edit
\`\`\`

### Adding a New Secret

1. Add the key: \`./scripts/sops.sh set my_new_secret value\`
2. Declare it in the relevant \`machines/<host>/services.nix\`:
   \`\`\`nix
   sops.secrets.my_new_secret = {};
   \`\`\`
3. Reference it in config: \`config.sops.secrets.my_new_secret.path\`

## Setup

### Install git hooks

\`\`\`bash
./scripts/install-hooks.sh
\`\`\`

This configures git to use \`.githooks/\`, which regenerates the README before every commit.

### Adding a New Host

1. Create \`machines/<name>/\` with at minimum: \`default.nix\`, \`hardware-configuration.nix\`, \`networking.nix\`, \`services.nix\`
2. Add age key to \`.sops.yaml\` and re-encrypt: \`./scripts/sops.sh edit\`
3. Add to \`flake.nix\` outputs
4. Deploy: \`./scripts/install.sh <name> <ip>\`

### Updating flake inputs

\`\`\`bash
nix flake update
git add flake.lock
git commit -m "chore: update flake.lock"
\`\`\`

## License

MIT
HEREDOC

echo "README.md generated."
