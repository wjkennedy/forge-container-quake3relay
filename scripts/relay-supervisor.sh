#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

FORGE_ENV="${FORGE_ENV:-development}"
FORGE_SITE="${FORGE_SITE:-a9data.atlassian.net}"
FORGE_PRODUCT="${FORGE_PRODUCT:-Jira}"
TUNNEL_MODE="${TUNNEL_MODE:-auto}"
SUPERVISOR_MODE="${SUPERVISOR_MODE:-loop}"
LOOP_INTERVAL_SECONDS="${LOOP_INTERVAL_SECONDS:-60}"
START_LOCAL_ON_BOOT="${START_LOCAL_ON_BOOT:-1}"
RESTART_LOCAL_ON_PUBLIC_FAILURE="${RESTART_LOCAL_ON_PUBLIC_FAILURE:-1}"
REDEPLOY_FORGE_ON_FAILURE="${REDEPLOY_FORGE_ON_FAILURE:-1}"
INITIAL_PUBLIC_GRACE_SECONDS="${INITIAL_PUBLIC_GRACE_SECONDS:-20}"

usage() {
  cat <<'EOF'
Keep the Forge relay demo reconciled from outside Forge.

This supervisor owns the parts Forge cannot:
- local Docker relay bringup
- local cloudflared bringup
- tunnel refresh via local restart
- Forge redeploy when the hosted service goes unhealthy

Usage:
  bash scripts/relay-supervisor.sh

Optional environment:
  SUPERVISOR_MODE                   once or loop. Default: loop
  LOOP_INTERVAL_SECONDS             Delay between checks in loop mode. Default: 60
  START_LOCAL_ON_BOOT               Run start-lan-party.sh before checks. Default: 1
  RESTART_LOCAL_ON_PUBLIC_FAILURE   Restart local relay+tunnel when public path fails. Default: 1
  REDEPLOY_FORGE_ON_FAILURE         Redeploy Forge when Forge health fails. Default: 1
  INITIAL_PUBLIC_GRACE_SECONDS      Wait after local restart before public recheck. Default: 20
  FORGE_ENV                         Forge environment. Default: development
  FORGE_SITE                        Atlassian site. Default: a9data.atlassian.net
  FORGE_PRODUCT                     Atlassian product. Default: Jira
  TUNNEL_MODE                       auto, local-managed, token. Default: auto
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

assert_forge() {
  FORGE_ENV="${FORGE_ENV}" FORGE_SITE="${FORGE_SITE}" FORGE_PRODUCT="${FORGE_PRODUCT}" \
    bash scripts/q3-relay-admin.sh assert-forge >/tmp/q3-relay-supervisor-forge.log 2>&1
}

assert_public() {
  bash scripts/q3-relay-admin.sh assert-public >/tmp/q3-relay-supervisor-public.log 2>&1
}

restart_local() {
  log "Restarting local relay+tunnel stack"
  TUNNEL_MODE="${TUNNEL_MODE}" bash scripts/q3-relay-admin.sh restart-local
}

redeploy_forge() {
  log "Redeploying Forge service"
  FORGE_ENV="${FORGE_ENV}" FORGE_SITE="${FORGE_SITE}" FORGE_PRODUCT="${FORGE_PRODUCT}" \
    bash scripts/q3-relay-admin.sh restart-forge
}

ensure_local_bootstrap() {
  if [[ "${START_LOCAL_ON_BOOT}" != "1" ]]; then
    return 0
  fi

  log "Ensuring local relay+tunnel stack is up"
  if assert_public; then
    log "Public relay already healthy"
    return 0
  fi

  restart_local
  sleep "${INITIAL_PUBLIC_GRACE_SECONDS}"
}

handle_forge_failure() {
  log "Forge health check failed"
  sed -n '1,20p' /tmp/q3-relay-supervisor-forge.log || true

  if [[ "${REDEPLOY_FORGE_ON_FAILURE}" != "1" ]]; then
    return 1
  fi

  redeploy_forge
}

handle_public_failure() {
  log "Public relay check failed"
  sed -n '1,20p' /tmp/q3-relay-supervisor-public.log || true

  if [[ "${RESTART_LOCAL_ON_PUBLIC_FAILURE}" != "1" ]]; then
    return 1
  fi

  restart_local
  sleep "${INITIAL_PUBLIC_GRACE_SECONDS}"
}

run_check_cycle() {
  if ! assert_forge; then
    handle_forge_failure
  else
    log "Forge health: ok"
  fi

  if ! assert_public; then
    handle_public_failure
  else
    log "Public relay: ok"
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_cmd bash
  require_cmd forge
  require_cmd docker
  require_cmd curl
  require_cmd node

  ensure_local_bootstrap

  case "${SUPERVISOR_MODE}" in
    once)
      run_check_cycle
      ;;
    loop)
      while true; do
        run_check_cycle
        sleep "${LOOP_INTERVAL_SECONDS}"
      done
      ;;
    *)
      echo "Unsupported SUPERVISOR_MODE=${SUPERVISOR_MODE}. Use once or loop." >&2
      exit 1
      ;;
  esac
}

main "$@"
