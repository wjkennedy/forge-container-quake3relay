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
GAME_PID_FILE="${GAME_PID_FILE:-/tmp/q3-game.pid}"
RELAY_PID_FILE="${RELAY_PID_FILE:-/tmp/q3-relay.pid}"
CLOUDFLARED_PID_FILE="${CLOUDFLARED_PID_FILE:-/tmp/cloudflared.pid}"
CLOUDFLARED_LOG_TAIL_PID=""

Q3_HOME="${Q3_HOME:-/tmp/ioquake3-home}"
mkdir -p "$Q3_HOME/baseq3" /tmp/forge-q3

if [ -f /opt/ioquake3/demoq3/pak0.pk3 ]; then
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

  echo "Starting q3 mock UDP server because pak0.pk3 is not present." >&2
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

start_cloudflared_log_tail() {
  if [[ "${ENABLE_CLOUDFLARED}" != "true" && "${ENABLE_CLOUDFLARED}" != "1" ]]; then
    return 0
  fi

  : > "${CLOUDFLARED_TUNNEL_LOG}"
  (
    tail -n 0 -F "${CLOUDFLARED_TUNNEL_LOG}" 2>/dev/null \
      | sed -u 's/^/[cloudflared] /'
  ) &
  CLOUDFLARED_LOG_TAIL_PID="$!"
}

start_cloudflared() {
  if [[ "${ENABLE_CLOUDFLARED}" != "true" && "${ENABLE_CLOUDFLARED}" != "1" ]]; then
    return 0
  fi

  if [[ -z "${CLOUDFLARED_TOKEN:-}" ]]; then
    echo "ENABLE_CLOUDFLARED is set, but CLOUDFLARED_TOKEN is empty." >&2
    exit 1
  fi

  echo "Starting cloudflared tunnel to ${CLOUDFLARED_ORIGIN_URL}" >&2
  /usr/local/bin/cloudflared \
    tunnel \
    --no-autoupdate \
    --protocol "${CLOUDFLARED_PROTOCOL}" \
    --url "${CLOUDFLARED_ORIGIN_URL}" \
    run \
    --token "${CLOUDFLARED_TOKEN}" >>"${CLOUDFLARED_TUNNEL_LOG}" 2>&1 &
  CLOUDFLARED_PID="$!"
  printf '%s\n' "${CLOUDFLARED_PID}" > "${CLOUDFLARED_PID_FILE}"
}

if [[ "${ENABLE_CLOUDFLARED}" == "true" || "${ENABLE_CLOUDFLARED}" == "1" ]]; then
  start_cloudflared_log_tail
  start_cloudflared
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
  fi

  sleep 2
done
