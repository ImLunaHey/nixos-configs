#!/usr/bin/env bash
HOST=$(hostname)
VALID_HOSTS=($(ls machines/))

if [[ ! " ${VALID_HOSTS[@]} " =~ " ${HOST} " ]]; then
  echo "Error: Unknown host '$HOST'. Valid hosts are: ${VALID_HOSTS[*]}"
  exit 1
fi

echo "Updating $HOST..."
nixos-rebuild switch --flake ".#$HOST"