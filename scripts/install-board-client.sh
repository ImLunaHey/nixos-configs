#!/usr/bin/env bash
# Installs only the CLI wrapper; does not adopt this Mac into nix-darwin.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
package_link="$HOME/.local/state/board-package"
mkdir -p "$HOME/.local/state" "$HOME/.local/bin"
for command in board vb; do
  target="$HOME/.local/bin/$command"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if ! grep -q 'board-package/bin/board' "$target" 2>/dev/null; then
      echo "Refusing to overwrite existing $target" >&2
      exit 1
    fi
  fi
done
nix build "$repo#board" --out-link "$package_link"
cat > "$HOME/.local/bin/board" <<'WRAPPER'
#!/bin/sh
: "${BOARD_URL:=https://lake.tail3275e2.ts.net:4101/api/board}"
export BOARD_URL
exec "$HOME/.local/state/board-package/bin/board" "$@"
WRAPPER
chmod +x "$HOME/.local/bin/board"
ln -sfn board "$HOME/.local/bin/vb"
"$HOME/.local/bin/board" --version
