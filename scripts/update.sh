#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'Host-side pull updates have been retired.' 'From your checkout, use: python3 scripts/deploy.py <host>' >&2
exit 1
