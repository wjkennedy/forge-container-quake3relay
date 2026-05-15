#!/bin/sh
set -eu

GAME_PORT="${GAME_PORT:-27960}"
SERVER_PORT="${SERVER_PORT:-${PROXY_PORT:-8080}}"
export PROXY_PORT="$SERVER_PORT"
export TARGET_HOST="${TARGET_HOST:-127.0.0.1}"
export TARGET_PORT="${TARGET_PORT:-$GAME_PORT}"
export HOME="${HOME:-/tmp}"

Q3_HOME="${Q3_HOME:-/tmp/ioquake3-home}"
mkdir -p "$Q3_HOME/baseq3" /tmp/forge-q3

if [ -f /opt/ioquake3/demoq3/pak0.pk3 ]; then
  /usr/lib/ioquake3/ioq3ded \
    +set dedicated 2 \
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
    +set dedicated 2 \
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

shutdown() {
  kill "$GAME_PID" 2>/dev/null || true
  wait "$GAME_PID" 2>/dev/null || true
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

wait "$RELAY_PID"
RELAY_STATUS="$?"
shutdown
exit "$RELAY_STATUS"
