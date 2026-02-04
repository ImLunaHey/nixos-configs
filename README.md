# Luna's NixOS Configurations

Personal NixOS system configurations managed with [flakes](https://nixos.wiki/wiki/Flakes) and [sops-nix](https://github.com/Mic92/sops-nix) for encrypted secrets.

## Structure

```
nixos-configs/
├── flake.nix              # Flake entry point with host definitions
├── common.nix             # Shared configuration for all hosts
├── nova.nix               # Host-specific config for "nova"
├── hardware/
│   └── nova-hardware.nix  # Hardware config for nova
├── secrets/
│   └── secrets.yaml       # Encrypted secrets (gitignored)
└── .sops.yaml             # SOPS age key definitions
```

## Hosts

| Host | Purpose | Key Services |
|------|---------|--------------|
| `nova` | Media server & DNS | Jellyfin, Pi-hole, Docker, Tailscale |

## Quick Start

### Initial Setup

```bash
# Clone and enter directory
git clone https://github.com/yourusername/nixos-configs
cd nixos-configs

# Install NixOS configuration
sudo nixos-rebuild switch --flake .#nova
```

### Managing Secrets

Secrets are encrypted with [SOPS](https://github.com/mozilla/sops) using [age](https://github.com/FiloSottile/age).

```bash
# Edit secrets (requires age key file)
EDITOR=nano SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops secrets/secrets.yaml

# Rebuild to apply secrets
sudo nixos-rebuild switch --flake .#nova
```

#### Adding New Secrets

1. Edit `secrets/secrets.yaml`:
   ```yaml
   my_new_secret: {}
   ```

2. Rebuild to generate the secret file path

3. Reference in configuration:
   ```nix
   services.myService = {
     secretFile = config.sops.secrets.my_new_secret.path;
   };
   ```

#### Adding New Age Keys

Edit `.sops.yaml` to add new age keys:

```yaml
keys:
  - &luna age1amshxsjls4ma6u76mhd632228r4kz7kykmh72nvv4m590u8h8sdswe42l6
  - &nova age1kkwcc0eezy07yzxpunc74usx9vpfcg6g8f0fehpdalslptef6s0lt0cp

creation_rules:
  - path_regex: secrets/secrets.yaml$
    key_groups:
      - age:
          - *luna
          - *nova
   ```

## Configuration Details

### common.nix

Shared configuration applied to all hosts:
- Nix settings (experimental features, auto-optimise-store)
- Timezone (Europe/London) and locale (en_GB.UTF-8)
- Base packages: `vim`, `git`, `htop`, `btop`, `wget`, `curl`
- Hardened SSH (password auth disabled, root login restricted)
- GitHub SSH keys for root user

### nova.nix

Host-specific configuration for the `nova` host:

**Networking:**
- NetworkManager for desktop connectivity
- Tailscale VPN with auth key from secrets
- Firewall: ports 22 (SSH), 80 (Pi-hole), 8096 (Jellyfin), 53 (DNS)
- Tailscale interface trusted

**Hardware:**
- Intel GPU hardware acceleration for Jellyfin transcoding
- Intel media drivers: `intel-media-driver`, `intel-vaapi-driver`, `libva-vdpau-driver`

**Services:**
- Docker with weekly auto-prune
- Jellyfin container with GPU passthrough
- Pi-hole container for DNS sinkhole

### hardware/nova-hardware.nix

Host-specific hardware configuration (device drivers, kernel modules, etc.)

## Managing the Repository

### Adding a New Host

1. Create host config: `newhost.nix`
2. Create hardware config: `hardware/newhost-hardware.nix`
3. Update `flake.nix`:

   ```nix
   newhost = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     modules = [
       ./common.nix
       ./newhost.nix
       ./hardware/newhost-hardware.nix
       sops-nix.nixosModules.sops
     ];
   };
   ```

4. Add to `flake.nix` outputs
5. Rebuild: `sudo nixos-rebuild switch --flake .#newhost`

### Updating flake inputs

```bash
nix flake update
git add flake.lock
git commit -m "update flake.lock"
```

### Format nix files

```bash
nix fmt
```

## Development

### Prerequisites

- NixOS with flakes enabled
- Age key for secrets (see `.sops.yaml` for public keys)
- Sops-nix configured

### Testing Changes

```bash
# Dry-run to check for errors
sudo nixos-rebuild dry-activate --flake .#nova

# Apply changes
sudo nixos-rebuild switch --flake .#nova
```

## License

MIT
