#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-q3-relay}"

if [ "$#" -eq 0 ]; then
  echo "Usage: scripts/q3-rcon.sh <command ...>" >&2
  exit 1
fi

docker exec \
  -e RCON_HOST="${RCON_HOST:-127.0.0.1}" \
  -e RCON_PORT="${RCON_PORT:-27960}" \
  -e RCON_PASSWORD="${RCON_PASSWORD:-sphere}" \
  -e RCON_TCP="${RCON_TCP:-false}" \
  -e RCON_CHALLENGE="${RCON_CHALLENGE:-false}" \
  -e RCON_TIMEOUT_MS="${RCON_TIMEOUT_MS:-5000}" \
  "$CONTAINER_NAME" \
  node /opt/forge-q3/scripts/rcon-client.mjs "$@"
