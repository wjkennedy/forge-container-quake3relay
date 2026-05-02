#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not on PATH." >&2
  exit 1
fi

echo "RCON shell connected to q3-relay."
echo "Type Quake 3 server commands. Type 'exit' or press Ctrl-D to leave."

while true; do
  printf 'rcon> '
  if ! IFS= read -r command; then
    echo
    break
  fi

  case "${command}" in
    "" )
      continue
      ;;
    exit|quit )
      break
      ;;
  esac

  bash scripts/q3-rcon.sh "${command}"
done
