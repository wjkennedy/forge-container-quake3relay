#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

load_dotenv_defaults() {
  [[ -f .env ]] || return 0

  local line key
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue

    key="${line%%=*}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

    if [[ -z "${!key+x}" ]]; then
      eval "export ${line}"
    fi
  done < .env
}

DEFAULT_PUBLIC_HOSTNAME="q3a.a9group.net"
DEFAULT_LOCAL_HOST_PORT="${HOST_PORT:-8080}"
DEFAULT_FORGE_ENV="${FORGE_ENV:-development}"
DEFAULT_FORGE_SITE="${FORGE_SITE:-a9data.atlassian.net}"
DEFAULT_FORGE_PRODUCT="${FORGE_PRODUCT:-Jira}"
DEFAULT_SERVICE_KEY="${FORGE_SERVICE_KEY:-q3-relay}"
DEFAULT_WEBTRIGGER_KEY="${FORGE_WEBTRIGGER_KEY:-q3-relay-health-trigger}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/q3-relay-admin.sh <command>

Commands:
  status           Show Forge service status and health via web trigger.
  public           Show public hostname DNS, HTTPS health, and WebSocket status.
  status-all       Show Forge status plus public relay checks.
  assert-forge     Exit non-zero unless the Forge health endpoint is healthy.
  assert-public    Exit non-zero unless the public HTTPS and WebSocket relay are healthy.
  restart          Redeploy the Forge app to restart the hosted service.
  watch            Watch Forge service state changes.
  health           Print the Forge health web trigger response only.
  restart-local    Restart the local Docker relay + Cloudflare tunnel stack.
  restart-forge    Alias for restart.
  status-local     Show local Docker, local health, public tunnel, and Forge status.
  logs             Show recent local Docker logs for relay and tunnel.
  doctor           Alias for status.

Environment:
  HOST_PORT        Local exposed relay port. Default: 8080
  TUNNEL_MODE      Tunnel mode for local stack. auto, local-managed, token.
  FORGE_ENV        Forge environment name. Default: development
  FORGE_SITE       Atlassian site for web trigger lookup. Default: a9data.atlassian.net
  FORGE_PRODUCT    Atlassian product for install lookup. Default: Jira
  FORGE_SERVICE_KEY Forge service key. Default: q3-relay
  FORGE_WEBTRIGGER_KEY Web trigger key. Default: q3-relay-health-trigger
  PUBLIC_HOSTNAME  Public Cloudflare hostname. Default: q3a.a9group.net
EOF
}

PUBLIC_HOSTNAME="${PUBLIC_HOSTNAME:-$DEFAULT_PUBLIC_HOSTNAME}"
HOST_PORT="${HOST_PORT:-$DEFAULT_LOCAL_HOST_PORT}"
FORGE_ENV="${FORGE_ENV:-$DEFAULT_FORGE_ENV}"
FORGE_SITE="${FORGE_SITE:-$DEFAULT_FORGE_SITE}"
FORGE_PRODUCT="${FORGE_PRODUCT:-$DEFAULT_FORGE_PRODUCT}"
FORGE_SERVICE_KEY="${FORGE_SERVICE_KEY:-$DEFAULT_SERVICE_KEY}"
FORGE_WEBTRIGGER_KEY="${FORGE_WEBTRIGGER_KEY:-$DEFAULT_WEBTRIGGER_KEY}"

load_env_files() {
  load_dotenv_defaults

  if [[ -f .cloudflared/runtime.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .cloudflared/runtime.env
    set +a
  fi
}

resolve_compose_files() {
  local mode="${TUNNEL_MODE:-auto}"

  if [[ -x "${ROOT_DIR}/scripts/prepare-cloudflared-tunnel.sh" ]]; then
    "${ROOT_DIR}/scripts/prepare-cloudflared-tunnel.sh" >/dev/null 2>&1 || true
  fi

  if [[ -f .cloudflared/runtime.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .cloudflared/runtime.env
    set +a
    mode="${CLOUDFLARED_TUNNEL_MODE:-$mode}"
  fi

  case "${mode}" in
    local-managed)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.cloudflare-local.yml)
      TUNNEL_SERVICE_NAME="cloudflared-local"
      ;;
    token)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.cloudflare-token.yml)
      TUNNEL_SERVICE_NAME="cloudflared-named"
      ;;
    *)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.cloudflare-local.yml)
      TUNNEL_SERVICE_NAME="cloudflared-local"
      ;;
  esac
}

print_header() {
  printf '\n== %s ==\n' "$1"
}

require_forge() {
  if ! command -v forge >/dev/null 2>&1; then
    echo "forge CLI not installed" >&2
    exit 1
  fi
}

check_local_health() {
  local url="http://127.0.0.1:${HOST_PORT}/healthz"
  if curl -fsS --max-time 5 "${url}" >/dev/null 2>&1; then
    echo "local health: ok (${url})"
    curl -fsS --max-time 5 "${url}" || true
    printf '\n'
  else
    echo "local health: down (${url})"
  fi
}

check_public_health() {
  local url="https://${PUBLIC_HOSTNAME}/healthz"
  if curl -fsS --max-time 10 "${url}" >/dev/null 2>&1; then
    echo "public health: ok (${url})"
    curl -fsS --max-time 10 "${url}" || true
    printf '\n'
  else
    echo "public health: down (${url})"
  fi
}

show_public_dns() {
  if command -v dig >/dev/null 2>&1; then
    echo "public dns:"
    dig +short "${PUBLIC_HOSTNAME}" || true
  else
    echo "public dns: dig not installed"
  fi
}

check_public_websocket() {
  if RELAY_URL="wss://${PUBLIC_HOSTNAME}" node scripts/check-relay-websocket.mjs >/tmp/q3-relay-ws-check.log 2>&1; then
    echo "public websocket: ok (wss://${PUBLIC_HOSTNAME})"
    sed -n '1,5p' /tmp/q3-relay-ws-check.log
  else
    echo "public websocket: down (wss://${PUBLIC_HOSTNAME})"
    sed -n '1,20p' /tmp/q3-relay-ws-check.log || true
  fi
}

assert_public_healthy() {
  local url="https://${PUBLIC_HOSTNAME}/healthz"

  if ! curl -fsS --max-time 10 "${url}" >/tmp/q3-relay-public-health.json 2>/tmp/q3-relay-public-health.err; then
    echo "public health: down (${url})" >&2
    sed -n '1,20p' /tmp/q3-relay-public-health.err >&2 || true
    return 1
  fi

  if ! RELAY_URL="wss://${PUBLIC_HOSTNAME}" node scripts/check-relay-websocket.mjs >/tmp/q3-relay-public-ws.log 2>&1; then
    echo "public websocket: down (wss://${PUBLIC_HOSTNAME})" >&2
    sed -n '1,20p' /tmp/q3-relay-public-ws.log >&2 || true
    return 1
  fi

  echo "public health: ok (${url})"
  sed -n '1,5p' /tmp/q3-relay-public-health.json
  echo "public websocket: ok (wss://${PUBLIC_HOSTNAME})"
  sed -n '1,5p' /tmp/q3-relay-public-ws.log
}

show_public_status() {
  print_header "Public Relay"
  echo "public hostname: ${PUBLIC_HOSTNAME}"
  show_public_dns
  check_public_health
  check_public_websocket
}

show_local_status() {
  print_header "Local Docker"
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker not installed"
    return
  fi

  resolve_compose_files
  docker compose "${COMPOSE_FILES[@]}" ps || true
}

show_forge_status() {
  print_header "Forge Service"
  require_forge
  forge show services -e "${FORGE_ENV}" -s "${FORGE_SERVICE_KEY}" --json || true
}

get_forge_health_url() {
  require_forge

  local output
  output="$(forge webtrigger create \
    -e "${FORGE_ENV}" \
    -s "${FORGE_SITE}" \
    -p "${FORGE_PRODUCT}" \
    -f "${FORGE_WEBTRIGGER_KEY}" 2>/dev/null || true)"

  printf '%s\n' "${output}" | grep -Eo 'https://[^[:space:]]+' | tail -n 1
}

show_forge_health() {
  print_header "Forge Health"
  local url
  url="$(get_forge_health_url)"

  if [[ -z "${url}" ]]; then
    echo "forge health url: unavailable"
    echo "site=${FORGE_SITE} product=${FORGE_PRODUCT} trigger=${FORGE_WEBTRIGGER_KEY}"
    return
  fi

  echo "forge health url: ${url}"
  if curl -fsS --max-time 20 "${url}" >/dev/null 2>&1; then
    echo "forge health: ok"
    curl -fsS --max-time 20 "${url}" || true
    printf '\n'
  else
    echo "forge health: down"
  fi
}

assert_forge_healthy() {
  local url
  url="$(get_forge_health_url)"

  if [[ -z "${url}" ]]; then
    echo "forge health url: unavailable" >&2
    return 1
  fi

  if ! curl -fsS --max-time 20 "${url}" >/tmp/q3-relay-forge-health.json 2>/tmp/q3-relay-forge-health.err; then
    echo "forge health: down (${url})" >&2
    sed -n '1,20p' /tmp/q3-relay-forge-health.err >&2 || true
    return 1
  fi

  echo "forge health: ok (${url})"
  sed -n '1,5p' /tmp/q3-relay-forge-health.json
}

show_network_checks() {
  print_header "Network Checks"
  echo "public hostname: ${PUBLIC_HOSTNAME}"
  check_local_health
  check_public_health
  check_public_websocket
}

show_logs() {
  resolve_compose_files
  docker compose "${COMPOSE_FILES[@]}" logs --tail=120 q3-relay "${TUNNEL_SERVICE_NAME}"
}

restart_local() {
  print_header "Restarting Local Stack"
  TUNNEL_MODE="${TUNNEL_MODE:-${CLOUDFLARED_TUNNEL_MODE:-local-managed}}" bash stop-lan-party.sh || true
  TUNNEL_MODE="${TUNNEL_MODE:-${CLOUDFLARED_TUNNEL_MODE:-local-managed}}" bash start-lan-party.sh
}

restart_forge() {
  print_header "Redeploying Forge Service"
  require_forge
  forge deploy -e "${FORGE_ENV}" --non-interactive
}

watch_forge() {
  require_forge
  forge show services -e "${FORGE_ENV}" -s "${FORGE_SERVICE_KEY}" -w
}

main() {
  load_env_files

  case "${1:-}" in
    status|doctor)
      show_forge_status
      show_forge_health
      ;;
    public)
      show_public_status
      ;;
    status-all)
      show_forge_status
      show_forge_health
      show_public_status
      ;;
    status-local)
      show_local_status
      show_network_checks
      show_forge_status
      show_forge_health
      ;;
    health)
      show_forge_health
      ;;
    assert-forge)
      assert_forge_healthy
      ;;
    assert-public)
      assert_public_healthy
      ;;
    restart|restart-forge)
      restart_forge
      ;;
    watch)
      watch_forge
      ;;
    restart-local)
      restart_local
      ;;
    logs)
      show_logs
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      echo "Unknown command: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "${@}"
