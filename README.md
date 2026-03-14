# Luna's NixOS Configurations

Personal NixOS system configurations managed with [flakes](https://nixos.wiki/wiki/Flakes) and [sops-nix](https://github.com/Mic92/sops-nix) for encrypted secrets.

> **This file is auto-generated.** Edit `scripts/generate-readme.sh` to change its contents.

## Structure

```
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
```

## Machines

| Host | IP | Purpose | Key Services |
|------|----|---------|--------------|
| `gilbert` | `192.168.0.11` | Media ripping (ARM), Minecraft server, NFS storage | Minecraft (ATM10),`arm` |
| `nova` | `192.168.0.10` | Media server, reverse proxy, Matrix homeserver | Matrix-Synapse,Caddy,`jellyfin`,`pihole`,`uptime-kuma`,`gotify`,`igotify`,`rustfs` |
| `void` | `192.168.0.12` | NAS with ZFS RAID storage | ZFS + SMART monitoring |

## Machine Details

### `gilbert`

**IP:** `192.168.0.11` &nbsp; **Purpose:** Media ripping (ARM), Minecraft server, NFS storage

| File | Role |
|------|------|
| `containers.nix` | Docker container definitions |
| `default.nix` | Imports all machine modules |
| `hardware-configuration.nix` | Generated hardware config (do not edit) |
| `hardware.nix` | GPU drivers and hardware acceleration |
| `minecraft.nix` | Minecraft server (ATM10 / NeoForge) |
| `networking.nix` | Static IP, firewall, Tailscale |
| `services.nix` | SOPS secret declarations |
| `storage.nix` | Disk mounts and NFS |
| `arm-config/` | ARM app config (`arm.yaml`) + `Dockerfile` |

### `nova`

**IP:** `192.168.0.10` &nbsp; **Purpose:** Media server, reverse proxy, Matrix homeserver

| File | Role |
|------|------|
| `caddy.nix` | Reverse proxy virtual hosts |
| `containers.nix` | Docker container definitions |
| `default.nix` | Imports all machine modules |
| `hardware-configuration.nix` | Generated hardware config (do not edit) |
| `hardware.nix` | GPU drivers and hardware acceleration |
| `matrix.nix` | Matrix-Synapse homeserver + PostgreSQL |
| `networking.nix` | Static IP, firewall, Tailscale |
| `services.nix` | SOPS secret declarations |
| `storage.nix` | Disk mounts and NFS |

### `void`

**IP:** `192.168.0.12` &nbsp; **Purpose:** NAS with ZFS RAID storage

| File | Role |
|------|------|
| `default.nix` | Imports all machine modules |
| `hardware-configuration.nix` | Generated hardware config (do not edit) |
| `networking.nix` | Static IP, firewall, Tailscale |
| `services.nix` | SOPS secret declarations |
| `smartd.nix` | SMART disk monitoring + notifications |
| `storage.nix` | Disk mounts and NFS |

## Common Configuration (`common.nix`)

Applied to every host:

- **Nix:** flakes + nix-command enabled, auto-optimise-store
- **Timezone:** Europe/London, locale en\_GB.UTF-8
- **Packages:** nano, tree, git, btop, wget, curl
- **SSH:** password auth disabled, root login restricted; keys imported from GitHub
- **Tailscale:** enabled on all hosts with routing features
- **Auto-upgrade:** polls `github:imlunahey/nixos-configs` every 15 minutes, reboots if needed
- **Gotify notification:** sent when a host successfully upgrades to a new generation

## Flake Inputs

| Input | Source |
|-------|--------|
| `inputs` | github:NixOS/nixpkgs/nixos-unstable |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/generate-readme.sh` | Regenerate this README from repo structure |
| `scripts/install-hooks.sh` | Configure git to use `.githooks/` |
| `scripts/update.sh` | `git pull` then `nixos-rebuild switch` on the current host |
| `scripts/install.sh <machine> <ip>` | Bootstrap any machine from a NixOS live ISO via nixos-anywhere |
| `scripts/sops.sh <cmd>` | list / get / set / delete / edit secrets |

## Secrets Management

Secrets are encrypted with [SOPS](https://github.com/mozilla/sops) + [age](https://github.com/FiloSottile/age).

Each machine decrypts secrets via its host SSH key (`/etc/ssh/ssh_host_ed25519_key`). Age keys are defined in `.sops.yaml`.

```bash
# List secrets
./scripts/sops.sh list

# Get a secret
./scripts/sops.sh get tailscale_key

# Add or update a secret
./scripts/sops.sh set my_secret my_value

# Open in editor
./scripts/sops.sh edit
```

### Adding a New Secret

1. Add the key: `./scripts/sops.sh set my_new_secret value`
2. Declare it in the relevant `machines/<host>/services.nix`:
   ```nix
   sops.secrets.my_new_secret = {};
   ```
3. Reference it in config: `config.sops.secrets.my_new_secret.path`

## Setup

### Install git hooks

```bash
./scripts/install-hooks.sh
```

This configures git to use `.githooks/`, which regenerates the README before every commit.

### Adding a New Host

1. Create `machines/<name>/` with at minimum: `default.nix`, `hardware-configuration.nix`, `networking.nix`, `services.nix`
2. Add age key to `.sops.yaml` and re-encrypt: `./scripts/sops.sh edit`
3. Add to `flake.nix` outputs
4. Deploy: `./scripts/install.sh <name> <ip>`

### Updating flake inputs

```bash
nix flake update
git add flake.lock
git commit -m "chore: update flake.lock"
```

## License

MIT
