#!/usr/bin/env bash
SOPS_FILE="secrets/secrets.yaml"
SOPS_AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"

run_sops() {
  nix-shell -p sops --run "SOPS_AGE_KEY_FILE=$SOPS_AGE_KEY_FILE sops $*"
}

usage() {
  echo "Usage: ./scripts/sops.sh <command> [args]"
  echo ""
  echo "Commands:"
  echo "  list              List all secret keys"
  echo "  get <key>         Get a secret value"
  echo "  set <key> <value> Add or update a secret"
  echo "  delete <key>      Delete a secret"
  echo "  edit              Open secrets file in editor"
  exit 1
}

case "$1" in
  list)
    run_sops "-d $SOPS_FILE" | grep -o '^[^:]*'
    ;;
  get)
    [ -z "$2" ] && { echo "Error: key required"; exit 1; }
    run_sops "-d --extract '[\"$2\"]' $SOPS_FILE"
    ;;
  set)
    [ -z "$2" ] || [ -z "$3" ] && { echo "Error: key and value required"; exit 1; }
    run_sops "--set '[\"$2\"] \"$3\"' $SOPS_FILE"
    ;;
  delete)
    [ -z "$2" ] && { echo "Error: key required"; exit 1; }
    run_sops "--unset '[\"$2\"]' $SOPS_FILE"
    ;;
  edit)
    run_sops "$SOPS_FILE"
    ;;
  *)
    usage
    ;;
esac