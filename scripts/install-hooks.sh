#!/usr/bin/env bash
# Configures git to use the .githooks/ directory for this repo.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git -C "$REPO_ROOT" config core.hooksPath .githooks
chmod +x "$REPO_ROOT/.githooks/pre-commit"

echo "Git hooks installed. Pre-commit hook will regenerate README.md on each commit."
