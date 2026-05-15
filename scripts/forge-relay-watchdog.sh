#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

FORGE_ENV="${FORGE_ENV:-development}"
FORGE_SITE="${FORGE_SITE:-a9data.atlassian.net}"
FORGE_PRODUCT="${FORGE_PRODUCT:-Jira}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-2}"
RECHECK_DELAY_SECONDS="${RECHECK_DELAY_SECONDS:-20}"
REDEPLOY_ON_FAILURE="${REDEPLOY_ON_FAILURE:-1}"
CHECK_PUBLIC="${CHECK_PUBLIC:-0}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

assert_forge() {
  FORGE_ENV="${FORGE_ENV}" FORGE_SITE="${FORGE_SITE}" FORGE_PRODUCT="${FORGE_PRODUCT}" \
    bash scripts/q3-relay-admin.sh assert-forge
}

assert_public() {
  bash scripts/q3-relay-admin.sh assert-public
}

restart_forge() {
  FORGE_ENV="${FORGE_ENV}" FORGE_SITE="${FORGE_SITE}" FORGE_PRODUCT="${FORGE_PRODUCT}" \
    bash scripts/q3-relay-admin.sh restart
}

main() {
  require_cmd bash
  require_cmd forge
  require_cmd curl
  require_cmd node

  log "Checking Forge relay health in ${FORGE_ENV} for ${FORGE_SITE} (${FORGE_PRODUCT})"

  local attempt=1
  while (( attempt <= MAX_ATTEMPTS )); do
    if assert_forge; then
      if [[ "${CHECK_PUBLIC}" == "1" ]]; then
        log "Checking public relay path"
        assert_public
      fi
      log "Watchdog check passed"
      return 0
    fi

    if (( attempt < MAX_ATTEMPTS )); then
      log "Health check failed, retrying after ${RECHECK_DELAY_SECONDS}s"
      sleep "${RECHECK_DELAY_SECONDS}"
    fi

    ((attempt++))
  done

  log "Forge relay remained unhealthy after ${MAX_ATTEMPTS} attempts"

  if [[ "${REDEPLOY_ON_FAILURE}" != "1" ]]; then
    log "Automatic redeploy disabled"
    return 1
  fi

  log "Redeploying Forge relay"
  restart_forge

  log "Rechecking Forge relay after redeploy"
  sleep "${RECHECK_DELAY_SECONDS}"
  assert_forge

  if [[ "${CHECK_PUBLIC}" == "1" ]]; then
    log "Rechecking public relay path after redeploy"
    assert_public
  fi

  log "Watchdog recovery passed"
}

main "$@"
