#!/usr/bin/env bash
set -euo pipefail

GAME_PORT="${GAME_PORT:-27960}"
SERVER_PORT="${SERVER_PORT:-${PROXY_PORT:-8080}}"
DEDICATED_MODE="${DEDICATED_MODE:-1}"
export PROXY_PORT="$SERVER_PORT"
export TARGET_HOST="${TARGET_HOST:-127.0.0.1}"
export TARGET_PORT="${TARGET_PORT:-$GAME_PORT}"
export HOME="${HOME:-/tmp}"
ENABLE_CLOUDFLARED="${ENABLE_CLOUDFLARED:-false}"
CLOUDFLARED_PROTOCOL="${CLOUDFLARED_PROTOCOL:-http2}"
CLOUDFLARED_RESTART_DELAY_SECONDS="${CLOUDFLARED_RESTART_DELAY_SECONDS:-5}"
CLOUDFLARED_ORIGIN_URL="${CLOUDFLARED_ORIGIN_URL:-http://127.0.0.1:${SERVER_PORT}}"
CLOUDFLARED_TUNNEL_LOG="${CLOUDFLARED_TUNNEL_LOG:-/tmp/cloudflared.log}"
PUBLIC_HOSTNAME="${PUBLIC_HOSTNAME:-q3a.a9group.net}"
PUBLIC_HTTP_URL="${PUBLIC_HTTP_URL:-https://${PUBLIC_HOSTNAME}/healthz}"
PUBLIC_WS_URL="${PUBLIC_WS_URL:-wss://${PUBLIC_HOSTNAME}}"
STRICT_STARTUP_CHECKS="${STRICT_STARTUP_CHECKS:-1}"
STARTUP_PUBLIC_PATH_CHECK="${STARTUP_PUBLIC_PATH_CHECK:-auto}"
STARTUP_LOCAL_HEALTH_ATTEMPTS="${STARTUP_LOCAL_HEALTH_ATTEMPTS:-60}"
STARTUP_TUNNEL_ATTEMPTS="${STARTUP_TUNNEL_ATTEMPTS:-30}"
STARTUP_PUBLIC_ATTEMPTS="${STARTUP_PUBLIC_ATTEMPTS:-20}"
STARTUP_SLEEP_SECONDS="${STARTUP_SLEEP_SECONDS:-2}"
PUBLIC_RECHECK_INTERVAL_SECONDS="${PUBLIC_RECHECK_INTERVAL_SECONDS:-60}"
GAME_PID_FILE="${GAME_PID_FILE:-/tmp/q3-game.pid}"
RELAY_PID_FILE="${RELAY_PID_FILE:-/tmp/q3-relay.pid}"
CLOUDFLARED_PID_FILE="${CLOUDFLARED_PID_FILE:-/tmp/cloudflared.pid}"
CLOUDFLARED_LOG_TAIL_PID=""
WEBSOCKET_CHECK_SCRIPT="/opt/forge-q3/scripts/check-relay-websocket.mjs"
LAST_PUBLIC_CHECK_EPOCH=0

log() {
  printf '[entrypoint] %s\n' "$*" >&2
}

bool_state() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) echo "true" ;;
    *) echo "false" ;;
  esac
}

should_check_public_path_on_startup() {
  case "${STARTUP_PUBLIC_PATH_CHECK:-auto}" in
    1|true|TRUE|yes|YES|on|ON)
      echo "true"
      ;;
    0|false|FALSE|no|NO|off|OFF)
      echo "false"
      ;;
    auto|AUTO|"")
      if [[ "${ENABLE_CLOUDFLARED}" == "true" || "${ENABLE_CLOUDFLARED}" == "1" ]]; then
        echo "true"
      else
        echo "false"
      fi
      ;;
    *)
      echo "false"
      ;;
  esac
}

Q3_HOME="${Q3_HOME:-/tmp/ioquake3-home}"
mkdir -p "$Q3_HOME/baseq3" /tmp/forge-q3

log "booting all-in-one relay container"
log "server_port=${SERVER_PORT} game_port=${GAME_PORT} public_hostname=${PUBLIC_HOSTNAME}"
log "enable_cloudflared=$(bool_state "${ENABLE_CLOUDFLARED}") strict_startup_checks=$(bool_state "${STRICT_STARTUP_CHECKS}")"
log "startup_public_path_check=$(should_check_public_path_on_startup)"
if [[ -n "${CLOUDFLARED_TOKEN:-}" ]]; then
  log "cloudflared_token_present=true"
else
  log "cloudflared_token_present=false"
fi

if [ -f /opt/ioquake3/demoq3/pak0.pk3 ]; then
  log "starting ioquake3 with demoq3 assets"
  /usr/lib/ioquake3/ioq3ded \
    +set dedicated "$DEDICATED_MODE" \
    +set sv_pure 0 \
    +set net_ip 127.0.0.1 \
    +set net_port "$GAME_PORT" \
    +set fs_basepath /opt/ioquake3 \
    +set fs_homepath "$Q3_HOME" \
    +set com_basegame demoq3 \
    +set fs_basegame "" \
    +set fs_game "" \
    +exec server.cfg &
elif [ -f /opt/ioquake3/baseq3/pak0.pk3 ]; then
  log "starting ioquake3 with baseq3 assets"
  /usr/lib/ioquake3/ioq3ded \
    +set dedicated "$DEDICATED_MODE" \
    +set sv_pure 1 \
    +set net_ip 127.0.0.1 \
    +set net_port "$GAME_PORT" \
    +set fs_basepath /opt/ioquake3 \
    +set fs_homepath "$Q3_HOME" \
    +exec server.cfg &
else
  if [ "${ALLOW_START_WITHOUT_PAK0:-}" != "1" ]; then
    echo "Missing /opt/ioquake3/demoq3/pak0.pk3 or /opt/ioquake3/baseq3/pak0.pk3. Set ALLOW_START_WITHOUT_PAK0=1 for mock/smoke tests." >&2
    exit 1
  fi

  log "starting q3 mock UDP server because pak0.pk3 is not present"
  Q3MOCK_PORT="$GAME_PORT" node /opt/forge-q3/scripts/q3-mock-server.mjs &
fi

GAME_PID="$!"
printf '%s\n' "${GAME_PID}" > "${GAME_PID_FILE}"
RELAY_PID=""
CLOUDFLARED_PID=""

shutdown() {
  if [[ -n "${CLOUDFLARED_LOG_TAIL_PID}" ]]; then
    kill "${CLOUDFLARED_LOG_TAIL_PID}" 2>/dev/null || true
    wait "${CLOUDFLARED_LOG_TAIL_PID}" 2>/dev/null || true
  fi
  if [[ -n "${CLOUDFLARED_PID}" ]]; then
    kill "${CLOUDFLARED_PID}" 2>/dev/null || true
    wait "${CLOUDFLARED_PID}" 2>/dev/null || true
  fi
  if [[ -n "${RELAY_PID}" ]]; then
    kill "${RELAY_PID}" 2>/dev/null || true
    wait "${RELAY_PID}" 2>/dev/null || true
  fi
  kill "${GAME_PID}" 2>/dev/null || true
  wait "${GAME_PID}" 2>/dev/null || true
}

restart_cloudflared() {
  if [[ -z "${CLOUDFLARED_PID}" ]]; then
    return 0
  fi
  echo "Restarting cloudflared after public tunnel failure." >&2
  kill "${CLOUDFLARED_PID}" 2>/dev/null || true
  wait "${CLOUDFLARED_PID}" 2>/dev/null || true
  CLOUDFLARED_PID=""
  rm -f "${CLOUDFLARED_PID_FILE}"
  sleep "${CLOUDFLARED_RESTART_DELAY_SECONDS}"
  start_cloudflared
}

require_local_health() {
  local health_url="http://127.0.0.1:${SERVER_PORT}/healthz"
  log "waiting for local relay health at ${health_url}"
  for _ in $(seq 1 "${STARTUP_LOCAL_HEALTH_ATTEMPTS}"); do
    if curl -fsS "${health_url}" >/dev/null 2>&1; then
      log "local relay health passed"
      return 0
    fi
    sleep "${STARTUP_SLEEP_SECONDS}"
  done

  echo "Relay did not become healthy at ${health_url}." >&2
  return 1
}

require_tunnel_registration() {
  if [[ "${ENABLE_CLOUDFLARED}" != "true" && "${ENABLE_CLOUDFLARED}" != "1" ]]; then
    log "tunnel registration skipped because cloudflared is disabled"
    return 0
  fi

  log "waiting for cloudflared tunnel registration"
  local tunnel_logs=""
  for _ in $(seq 1 "${STARTUP_TUNNEL_ATTEMPTS}"); do
    tunnel_logs="$(tail -n 200 "${CLOUDFLARED_TUNNEL_LOG}" 2>/dev/null || true)"
    if grep -Eq 'Registered tunnel connection|Connection [A-Za-z0-9]+ registered|INF Registered tunnel connection' <<<"${tunnel_logs}"; then
      log "cloudflared tunnel registration passed"
      return 0
    fi
    if grep -Eqi 'unauthorized|invalid token|403|serve tunnel error|failed to dial|i/o timeout|http_status:404' <<<"${tunnel_logs}"; then
      echo "Cloudflared reported a tunnel startup failure." >&2
      echo "${tunnel_logs}" >&2
      return 1
    fi
    sleep "${STARTUP_SLEEP_SECONDS}"
  done

  echo "Cloudflared did not confirm a registered tunnel connection." >&2
  echo "${tunnel_logs}" >&2
  return 1
}

check_public_health_once() {
  curl -fsS --max-time 15 "${PUBLIC_HTTP_URL}" >/dev/null 2>&1
}

check_public_websocket_once() {
  RELAY_URL="${PUBLIC_WS_URL}" node "${WEBSOCKET_CHECK_SCRIPT}" >/dev/null 2>&1
}

require_public_path() {
  local attempts="${1:-${STARTUP_PUBLIC_ATTEMPTS}}"
  log "waiting for public relay path ${PUBLIC_HTTP_URL} / ${PUBLIC_WS_URL}"
  for _ in $(seq 1 "${attempts}"); do
    if check_public_health_once && check_public_websocket_once; then
      log "public relay path passed"
      return 0
    fi
    sleep "${STARTUP_SLEEP_SECONDS}"
  done

  echo "Public relay path did not become healthy: ${PUBLIC_HTTP_URL} / ${PUBLIC_WS_URL}" >&2
  return 1
}

trap shutdown INT TERM

for i in $(seq 1 50); do
  if nc -zu 127.0.0.1 "$GAME_PORT" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$GAME_PID" 2>/dev/null; then
    echo "Game process exited before becoming ready" >&2
    wait "$GAME_PID"
    exit 1
  fi
  sleep 1
done

node /opt/forge-q3/scripts/relay-server-enhanced.mjs &
RELAY_PID="$!"
printf '%s\n' "${RELAY_PID}" > "${RELAY_PID_FILE}"
log "relay process started pid=${RELAY_PID}"

start_cloudflared_log_tail() {
  if [[ "${ENABLE_CLOUDFLARED}" != "true" && "${ENABLE_CLOUDFLARED}" != "1" ]]; then
    log "cloudflared log tail skipped because cloudflared is disabled"
    return 0
  fi

  : > "${CLOUDFLARED_TUNNEL_LOG}"
  (
    tail -n 0 -F "${CLOUDFLARED_TUNNEL_LOG}" 2>/dev/null \
      | sed -u 's/^/[cloudflared] /'
  ) &
  CLOUDFLARED_LOG_TAIL_PID="$!"
  log "cloudflared log tail started pid=${CLOUDFLARED_LOG_TAIL_PID}"
}

start_cloudflared() {
  if [[ "${ENABLE_CLOUDFLARED}" != "true" && "${ENABLE_CLOUDFLARED}" != "1" ]]; then
    log "cloudflared start skipped because cloudflared is disabled"
    return 0
  fi

  if [[ -z "${CLOUDFLARED_TOKEN:-}" ]]; then
    echo "ENABLE_CLOUDFLARED is set, but CLOUDFLARED_TOKEN is empty." >&2
    exit 1
  fi

  log "starting cloudflared tunnel to ${CLOUDFLARED_ORIGIN_URL} with protocol=${CLOUDFLARED_PROTOCOL}"
  /usr/local/bin/cloudflared \
    tunnel \
    --no-autoupdate \
    --protocol "${CLOUDFLARED_PROTOCOL}" \
    --url "${CLOUDFLARED_ORIGIN_URL}" \
    run \
    --token "${CLOUDFLARED_TOKEN}" >>"${CLOUDFLARED_TUNNEL_LOG}" 2>&1 &
  CLOUDFLARED_PID="$!"
  printf '%s\n' "${CLOUDFLARED_PID}" > "${CLOUDFLARED_PID_FILE}"
  log "cloudflared process started pid=${CLOUDFLARED_PID}"
}

if [[ "${ENABLE_CLOUDFLARED}" == "true" || "${ENABLE_CLOUDFLARED}" == "1" ]]; then
  start_cloudflared_log_tail
  start_cloudflared
else
  log "cloudflared disabled for this container start"
fi

if [[ "${STRICT_STARTUP_CHECKS}" == "1" || "${STRICT_STARTUP_CHECKS}" == "true" ]]; then
  log "running strict startup checks"
  require_local_health
  require_tunnel_registration
  if [[ "$(should_check_public_path_on_startup)" == "true" ]]; then
    require_public_path
    LAST_PUBLIC_CHECK_EPOCH="$(date +%s)"
  else
    log "public path startup check skipped"
  fi
  log "strict startup checks passed"
else
  log "strict startup checks disabled"
fi

while true; do
  if ! kill -0 "${GAME_PID}" 2>/dev/null; then
    echo "Game process exited; letting Forge restart the container." >&2
    wait "${GAME_PID}" || true
    shutdown
    exit 1
  fi

  if ! kill -0 "${RELAY_PID}" 2>/dev/null; then
    echo "Relay process exited; letting Forge restart the container." >&2
    wait "${RELAY_PID}" || true
    shutdown
    exit 1
  fi

  if [[ -n "${CLOUDFLARED_PID}" ]] && ! kill -0 "${CLOUDFLARED_PID}" 2>/dev/null; then
    echo "cloudflared exited; restarting it after ${CLOUDFLARED_RESTART_DELAY_SECONDS}s." >&2
    wait "${CLOUDFLARED_PID}" || true
    CLOUDFLARED_PID=""
    rm -f "${CLOUDFLARED_PID_FILE}"
    sleep "${CLOUDFLARED_RESTART_DELAY_SECONDS}"
    start_cloudflared
    if [[ "${STRICT_STARTUP_CHECKS}" == "1" || "${STRICT_STARTUP_CHECKS}" == "true" ]]; then
      require_tunnel_registration
      if [[ "$(should_check_public_path_on_startup)" == "true" ]]; then
        require_public_path
        LAST_PUBLIC_CHECK_EPOCH="$(date +%s)"
      fi
    fi
  fi

  if [[ "${ENABLE_CLOUDFLARED}" == "true" || "${ENABLE_CLOUDFLARED}" == "1" ]]; then
    now_epoch="$(date +%s)"
    if (( now_epoch - LAST_PUBLIC_CHECK_EPOCH >= PUBLIC_RECHECK_INTERVAL_SECONDS )); then
      if ! check_public_health_once || ! check_public_websocket_once; then
        restart_cloudflared
        if [[ "${STRICT_STARTUP_CHECKS}" == "1" || "${STRICT_STARTUP_CHECKS}" == "true" ]]; then
          require_tunnel_registration
          require_public_path
        fi
      fi
      LAST_PUBLIC_CHECK_EPOCH="${now_epoch}"
    fi
  fi

  sleep 2
done
