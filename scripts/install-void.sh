#!/usr/bin/env bash
# Install NixOS on void via nix-anywhere.
#
# Prerequisites:
#   1. Boot void from a NixOS minimal ISO
#      Download: https://nixos.org/download/#nixos-iso
#   2. On the ISO, enable SSH and set a root password:
#        sudo systemctl start sshd
#        sudo passwd root
#   3. Find void's IP on the ISO:
#        ip addr
#   4. Run this script with that IP:
#        ./scripts/install-void.sh <ip>

set -euo pipefail

TARGET_IP="${1:-}"

if [[ -z "$TARGET_IP" ]]; then
  echo "Usage: $0 <target-ip>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Installing NixOS (void) on $TARGET_IP..."
echo "This will WIPE all disks on the target machine."
echo ""
read -rp "Are you sure? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

nix run github:nix-community/nixos-anywhere -- \
  --flake "$FLAKE_DIR#void" \
  root@"$TARGET_IP"

echo ""
echo "Install complete. void should be rebooting into NixOS."
echo ""
echo "Next steps:"
echo "  1. Get void's age key for SOPS:"
echo "       ssh-keyscan void | nix run nixpkgs#ssh-to-age"
echo "     (or by IP if DNS isn't set up yet):"
echo "       ssh-keyscan $TARGET_IP | nix run nixpkgs#ssh-to-age"
echo ""
echo "  2. Replace the placeholder key in .sops.yaml with the real one."
echo ""
echo "  3. Re-encrypt secrets:"
echo "       nix run nixpkgs#sops -- updatekeys secrets/secrets.yaml"
echo ""
echo "  4. Update networking.hostId in machines/void/hardware-configuration.nix:"
echo "       ssh root@$TARGET_IP 'head -c 8 /etc/machine-id'"
echo ""
echo "  5. Verify the network interface name:"
echo "       ssh root@$TARGET_IP 'ip link'"
echo "     Update networking.nix if it differs from enp3s0."
echo ""
echo "  6. Commit and push — void will auto-apply within 15 minutes."
