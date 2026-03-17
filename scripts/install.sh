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

nix run github:nix-community/nixos-anywhere -- \
  --flake "$FLAKE_DIR#$MACHINE" \
  root@"$TARGET_IP"

echo ""
echo "Install complete. $MACHINE should be rebooting into NixOS."
echo ""
echo "Next steps:"
echo ""
echo "  1. Get $MACHINE's age key for SOPS:"
echo "       ssh-keyscan $MACHINE | nix run nixpkgs#ssh-to-age"
echo "     (or by IP if DNS isn't set up yet):"
echo "       ssh-keyscan $TARGET_IP | nix run nixpkgs#ssh-to-age"
echo ""
echo "  2. Replace the placeholder key for $MACHINE in .sops.yaml with the real one."
echo ""
echo "  3. Re-encrypt secrets:"
echo "       nix run nixpkgs#sops -- updatekeys secrets/secrets.yaml"
echo ""
if $uses_zfs; then
  echo "  4. Update networking.hostId in machines/$MACHINE/hardware-configuration.nix:"
  echo "       ssh root@$TARGET_IP 'head -c 8 /etc/machine-id'"
  echo ""
  echo "  5. Verify the network interface name:"
  echo "       ssh root@$TARGET_IP 'ip link'"
  echo "     Update machines/$MACHINE/networking.nix if it differs from the placeholder."
  echo ""
  echo "  6. Update disk device paths to stable by-id paths in machines/$MACHINE/storage.nix:"
  echo "       ssh root@$TARGET_IP 'ls /dev/disk/by-id/ | grep -v part'"
  echo ""
  echo "  7. Commit and push — $MACHINE will auto-apply within 15 minutes."
else
  echo "  4. Verify the network interface name:"
  echo "       ssh root@$TARGET_IP 'ip link'"
  echo "     Update machines/$MACHINE/networking.nix if needed."
  echo ""
  echo "  5. Commit and push — $MACHINE will auto-apply within 15 minutes."
fi
