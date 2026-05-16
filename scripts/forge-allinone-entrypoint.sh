#!/usr/bin/env bash
set -euo pipefail

DELEGATE_PATH="/opt/forge-q3/scripts/forge-allinone-entrypoint.sh"

if [[ -x "${DELEGATE_PATH}" ]]; then
  exec "${DELEGATE_PATH}" "$@"
fi

echo "Managed entrypoint script not found at ${DELEGATE_PATH}." >&2
exit 1
