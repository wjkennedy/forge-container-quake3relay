#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

TUNNEL_MODE="${TUNNEL_MODE:-auto}"
PREPARE_TUNNEL_SCRIPT="${ROOT_DIR}/scripts/prepare-cloudflared-tunnel.sh"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not on PATH." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is not available." >&2
  exit 1
fi

if [[ -x "${PREPARE_TUNNEL_SCRIPT}" ]]; then
  "${PREPARE_TUNNEL_SCRIPT}" >/dev/null
fi

if [[ -f "${ROOT_DIR}/.cloudflared/runtime.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.cloudflared/runtime.env"
  set +a
  TUNNEL_MODE="${CLOUDFLARED_TUNNEL_MODE:-${TUNNEL_MODE}}"
fi

if [[ "${TUNNEL_MODE}" == "local-managed" ]]; then
  COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.cloudflare-local.yml)
else
  COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.cloudflare-token.yml)
fi

echo "Stopping Quake 3 relay and ${TUNNEL_MODE} Cloudflare tunnel..."
docker compose \
  "${COMPOSE_FILES[@]}" \
  down -v
