#!/usr/bin/env bash
# Install NixOS on a machine via nixos-anywhere.
#
# Prerequisites:
#   1. Boot the target machine from a NixOS minimal ISO
#      Download: https://nixos.org/download/#nixos-iso
#   2. On the ISO, enable SSH and set a root password:
#        sudo systemctl start sshd
#        sudo passwd root
#   3. Find the machine's IP on the ISO:
#        ip addr
#   4. Run this script:
#        ./scripts/install.sh <machine> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALID_MACHINES=($(ls "$FLAKE_DIR/machines/"))

usage() {
  echo "Usage: $0 <machine> <ip>"
  echo ""
  echo "Machines: ${VALID_MACHINES[*]}"
  exit 1
}

MACHINE="${1:-}"
TARGET_IP="${2:-}"

[[ -z "$MACHINE" || -z "$TARGET_IP" ]] && usage

if [[ ! -d "$FLAKE_DIR/machines/$MACHINE" ]]; then
  echo "Error: unknown machine '$MACHINE'. Valid machines: ${VALID_MACHINES[*]}"
  exit 1
fi

# Detect machine capabilities
uses_disko=false
uses_zfs=false
grep -q "disko.nixosModules.disko" "$FLAKE_DIR/flake.nix" && \
  grep -A10 "^      $MACHINE = " "$FLAKE_DIR/flake.nix" | grep -q "disko" && \
  uses_disko=true
grep -qr 'supportedFilesystems.*zfs\|"zfs"' "$FLAKE_DIR/machines/$MACHINE/" 2>/dev/null && \
  uses_zfs=true

echo "Installing NixOS ($MACHINE) on $TARGET_IP..."
if $uses_disko; then
  echo "Disk layout: managed by disko (disks will be wiped and partitioned automatically)."
else
  echo "Disk layout: not managed by disko — ensure disks are already partitioned."
fi
echo ""
read -rp "This will WIPE all disks on the target machine. Are you sure? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }

# Inject pre-generated SSH host key if one exists for this machine (keeps SOPS age key stable)
EXTRA_FILES_DIR=""
HOST_KEY_ENC="$FLAKE_DIR/secrets/host-keys/${MACHINE}_host_key.enc"
if [[ -f "$HOST_KEY_ENC" ]]; then
  echo "Found pre-generated host key for $MACHINE — injecting to keep SOPS age key stable."
  EXTRA_FILES_DIR="$(mktemp -d)"
  mkdir -p "$EXTRA_FILES_DIR/etc/ssh"
  sops --decrypt "$HOST_KEY_ENC" > "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key"
  sops --decrypt "${HOST_KEY_ENC%.enc}.pub.enc" > "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key.pub"
  chmod 600 "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key"
  chmod 644 "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key.pub"
fi

NIXOS_ANYWHERE_ARGS=(--flake "$FLAKE_DIR#$MACHINE" root@"$TARGET_IP")
[[ -n "$EXTRA_FILES_DIR" ]] && NIXOS_ANYWHERE_ARGS+=(--extra-files "$EXTRA_FILES_DIR")

nix run github:nix-community/nixos-anywhere -- "${NIXOS_ANYWHERE_ARGS[@]}"

[[ -n "$EXTRA_FILES_DIR" ]] && rm -rf "$EXTRA_FILES_DIR"

echo ""
echo "Install complete. $MACHINE should be rebooting into NixOS."
echo ""
if $uses_zfs; then
  echo "Next steps:"
  echo ""
  echo "  1. Update networking.hostId in machines/$MACHINE/hardware-configuration.nix:"
  echo "       ssh luna@$MACHINE 'head -c 8 /etc/machine-id'"
  echo ""
  echo "  2. Verify the network interface name:"
  echo "       ssh luna@$MACHINE 'ip link'"
  echo "     Update machines/$MACHINE/networking.nix if it differs from the placeholder."
  echo ""
  echo "  3. Commit and push — $MACHINE will auto-apply within 15 minutes."
else
  echo "Next steps:"
  echo ""
  echo "  1. Verify the network interface name:"
  echo "       ssh luna@$MACHINE 'ip link'"
  echo "     Update machines/$MACHINE/networking.nix if needed."
  echo ""
  echo "  2. Commit and push — $MACHINE will auto-apply within 15 minutes."
fi
