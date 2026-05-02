#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

LOCAL_SERVICE_NAME="q3-relay"
RCON_SHELL_SCRIPT="${ROOT_DIR}/rcon-shell.sh"
LOCAL_MANAGED_TUNNEL_SERVICE_NAME="cloudflared-local"
TOKEN_TUNNEL_SERVICE_NAME="cloudflared-named"
PREPARE_TUNNEL_SCRIPT="${ROOT_DIR}/scripts/prepare-cloudflared-tunnel.sh"
WEBSOCKET_CHECK_SCRIPT="${ROOT_DIR}/scripts/check-relay-websocket.mjs"
TUNNEL_MODE="${TUNNEL_MODE:-auto}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

HOST_PORT="${HOST_PORT:-8080}"
HEALTH_URL="http://127.0.0.1:${HOST_PORT}/healthz"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not on PATH." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is not available." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is not installed or not on PATH." >&2
  exit 1
fi

if command -v dig >/dev/null 2>&1; then
  HAVE_DIG=true
else
  HAVE_DIG=false
fi

if [[ ! -x "${PREPARE_TUNNEL_SCRIPT}" ]]; then
  echo "Missing tunnel preparation script: ${PREPARE_TUNNEL_SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${WEBSOCKET_CHECK_SCRIPT}" ]]; then
  echo "Missing WebSocket check script: ${WEBSOCKET_CHECK_SCRIPT}" >&2
  exit 1
fi

echo "Preparing Cloudflare tunnel runtime configuration..."
"${PREPARE_TUNNEL_SCRIPT}"

if [[ ! -f "${ROOT_DIR}/.cloudflared/runtime.env" ]]; then
  echo "Tunnel runtime environment was not generated." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "${ROOT_DIR}/.cloudflared/runtime.env"
set +a

PUBLIC_HOSTNAME="${CLOUDFLARED_PUBLIC_HOSTNAME:-q3a.a9group.net}"
PUBLIC_HTTP_URL="https://${PUBLIC_HOSTNAME}/healthz"
PUBLIC_WS_URL="wss://${PUBLIC_HOSTNAME}"

case "${CLOUDFLARED_TUNNEL_MODE}" in
  local-managed)
    COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.cloudflare-local.yml)
    TUNNEL_SERVICE_NAME="${LOCAL_MANAGED_TUNNEL_SERVICE_NAME}"
    ;;
  token)
    COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.cloudflare-token.yml)
    TUNNEL_SERVICE_NAME="${TOKEN_TUNNEL_SERVICE_NAME}"
    ;;
  *)
    echo "Unsupported prepared tunnel mode: ${CLOUDFLARED_TUNNEL_MODE}" >&2
    exit 1
    ;;
esac

echo "Checking Docker Compose configuration..."
if ! docker compose "${COMPOSE_FILES[@]}" config >/dev/null; then
  echo "Docker Compose configuration is invalid." >&2
  exit 1
fi

echo "Checking local relay port availability on ${HOST_PORT}..."
if ! python3 - <<'PY' "${HOST_PORT}"
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
then
  echo "Port ${HOST_PORT} is already in use. Set HOST_PORT to another port and retry." >&2
  exit 1
fi

echo "Removing stale LAN party containers from previous runs..."
docker compose "${COMPOSE_FILES[@]}" rm -sf "${LOCAL_SERVICE_NAME}" "${TUNNEL_SERVICE_NAME}" >/dev/null 2>&1 || true
docker rm -f q3-relay-cloudflared >/dev/null 2>&1 || true
docker rm -f q3-relay-cloudflared-local >/dev/null 2>&1 || true
docker rm -f q3-relay-cloudflared-named >/dev/null 2>&1 || true

echo "Starting Quake 3 relay with the ${CLOUDFLARED_TUNNEL_MODE} Cloudflare tunnel for ${PUBLIC_HOSTNAME}..."
docker compose \
  "${COMPOSE_FILES[@]}" \
  up -d --build --force-recreate --remove-orphans "${LOCAL_SERVICE_NAME}" "${TUNNEL_SERVICE_NAME}"

echo "Waiting for local relay health check at ${HEALTH_URL}..."
for _ in {1..60}; do
  if curl -fsS "${HEALTH_URL}" >/dev/null 2>&1; then
    break
  fi
  printf '.'
  sleep 2
done

echo
if ! curl -fsS "${HEALTH_URL}" >/dev/null 2>&1; then
  echo "Relay did not become healthy in time." >&2
  echo "Check logs with:" >&2
  echo "  docker compose ${COMPOSE_FILES[*]} logs ${LOCAL_SERVICE_NAME} ${TUNNEL_SERVICE_NAME}" >&2
  exit 1
fi

echo "Checking Cloudflare tunnel logs for a successful connection..."
for _ in {1..30}; do
  tunnel_logs="$(docker compose "${COMPOSE_FILES[@]}" logs --no-color "${TUNNEL_SERVICE_NAME}" 2>/dev/null || true)"
  if grep -Eq 'Registered tunnel connection|Connection [A-Za-z0-9]+ registered|INF Registered tunnel connection' <<<"${tunnel_logs}"; then
    break
  fi
  if grep -Eqi 'error|failed|unauthorized|invalid token|403|502' <<<"${tunnel_logs}"; then
    echo "Cloudflare tunnel reported an error during startup." >&2
    echo "${tunnel_logs}" >&2
    exit 1
  fi
  sleep 2
done

tunnel_logs="$(docker compose "${COMPOSE_FILES[@]}" logs --no-color "${TUNNEL_SERVICE_NAME}" 2>/dev/null || true)"
if ! grep -Eq 'Registered tunnel connection|Connection [A-Za-z0-9]+ registered|INF Registered tunnel connection' <<<"${tunnel_logs}"; then
  echo "Cloudflare tunnel did not confirm a successful connection." >&2
  echo "${tunnel_logs}" >&2
  exit 1
fi

if grep -Eq 'localhost:8080|\\\"service\\\":\\\"http://localhost:8080\\\"|\\\"service\\\":\\\"tcp://localhost:8080\\\"' <<<"${tunnel_logs}"; then
  echo "Cloudflare tunnel is connected, but its active ingress config still references localhost:8080." >&2
  echo "For this Docker stack, q3a.a9group.net must route only to http://q3-relay:8080." >&2
  echo "Remove any dashboard-managed public hostname rule for ${PUBLIC_HOSTNAME} that points to localhost:8080 or tcp://localhost:8080." >&2
  exit 1
fi

if grep -Eq '"ingress":\[\{"service":"http_status:404"\}\]|\\\"ingress\\\":\\\[\\\{\\\"service\\\":\\\"http_status:404\\\"\\\}\\\]' <<<"${tunnel_logs}"; then
  echo "Cloudflare tunnel is connected, but its active config only serves http_status:404." >&2
  echo "The hostname ${PUBLIC_HOSTNAME} is not attached to the tunnel yet." >&2
  echo "Ensure DNS routing is provisioned with 'cloudflared tunnel route dns ${CLOUDFLARED_TUNNEL_NAME:-q3-websocket} ${PUBLIC_HOSTNAME}'." >&2
  exit 1
fi

echo "Checking public health URL at ${PUBLIC_HTTP_URL}..."
public_check_used_resolve_fallback=false
if ! curl -fsS --max-time 15 "${PUBLIC_HTTP_URL}" >/dev/null 2>&1; then
  public_check_ok=false

  if [[ "${HAVE_DIG}" == "true" ]]; then
    while IFS= read -r resolved_ip; do
      [[ -n "${resolved_ip}" ]] || continue
      if curl -fsS --max-time 15 --resolve "${PUBLIC_HOSTNAME}:443:${resolved_ip}" "${PUBLIC_HTTP_URL}" >/dev/null 2>&1; then
        public_check_ok=true
        public_check_used_resolve_fallback=true
        break
      fi
    done < <(dig @1.1.1.1 +short "${PUBLIC_HOSTNAME}")
  fi

  if [[ "${public_check_ok}" != "true" ]]; then
    echo "Public health check failed for ${PUBLIC_HTTP_URL}." >&2
    echo "The local relay is up, but the public hostname is not routing correctly yet." >&2
    echo "Cloudflared logs:" >&2
    echo "${tunnel_logs}" >&2
    exit 1
  fi
fi

echo "Checking public WebSocket relay at ${PUBLIC_WS_URL}..."
if ! RELAY_URL="${PUBLIC_WS_URL}" node "${WEBSOCKET_CHECK_SCRIPT}" >/dev/null; then
  echo "Public WebSocket check failed for ${PUBLIC_WS_URL}." >&2
  exit 1
fi

if [[ "${public_check_used_resolve_fallback}" == "true" ]]; then
  echo "Warning: public DNS is live, but this machine's normal resolver still could not resolve ${PUBLIC_HOSTNAME}." >&2
  echo "Browser clients on this machine may fail to connect to ${PUBLIC_WS_URL} until local DNS cache/resolver state refreshes." >&2
fi

echo "LAN party relay is up."
echo "Public WebSocket URL: ${PUBLIC_WS_URL}"
echo "Public health URL:    ${PUBLIC_HTTP_URL}"
echo "Local health URL:     ${HEALTH_URL}"
echo
echo "Useful commands:"
echo "  docker compose ${COMPOSE_FILES[*]} logs -f ${LOCAL_SERVICE_NAME} ${TUNNEL_SERVICE_NAME}"
echo "  docker compose ${COMPOSE_FILES[*]} down -v"

if [[ -x "${RCON_SHELL_SCRIPT}" && -t 0 && -t 1 ]]; then
  echo
  exec "${RCON_SHELL_SCRIPT}"
fi
