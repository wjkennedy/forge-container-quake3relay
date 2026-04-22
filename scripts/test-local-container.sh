#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  docker compose -f docker-compose.yml -f docker-compose.test.yml down -v >/dev/null 2>&1 || true
}

trap cleanup EXIT

export HOST_PORT="${HOST_PORT:-18080}"

docker compose -f docker-compose.yml -f docker-compose.test.yml up -d --build q3-relay

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${HOST_PORT}/healthz" >/dev/null 2>&1; then
    RELAY_HOST=127.0.0.1 RELAY_PORT="$HOST_PORT" node tests/e2e/quake3-status.e2e.mjs
    exit 0
  fi
  sleep 1
done

docker compose -f docker-compose.yml -f docker-compose.test.yml logs q3-relay
echo "q3-relay did not become healthy at http://127.0.0.1:${HOST_PORT}/healthz" >&2
exit 1
