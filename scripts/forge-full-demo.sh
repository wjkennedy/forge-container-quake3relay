#!/usr/bin/env bash
set -euo pipefail

APP_ID="0fc32483-5342-46c9-9c21-2d5b6c68a963"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

usage() {
  cat <<'EOF'
Full Forge container demo workflow:

1. Ensure the Forge container repository exists.
2. Log Docker into the Forge registry.
3. Build the all-in-one Quake 3 image.
4. Push the tagged image to Forge.
5. Deploy the Forge app.
6. Upgrade the site installation.
7. Print follow-up health/status commands.

Usage:
  bash scripts/forge-full-demo.sh

Optional environment:
  TAG                  Image tag to publish. Default: q3-allinone-demo-<UTC timestamp>
  APP_ID               Forge app UUID. Defaults from manifest.yml.
  CONTAINER_KEY        Forge container key. Default: quake3-allinone
  ENVIRONMENT          Forge environment. Default: development
  SITE                 Atlassian site. Default: a9data.atlassian.net
  PRODUCT              Atlassian product. Default: Jira
  IMAGE_NAME           Local image name. Default: forge-q3-allinone
  SERVICE_DIR          Docker build context. Default: ./services/quake3-allinone
  PLATFORM             Docker platform. Default: linux/amd64
  DO_CREATE_CONTAINER  Run "forge containers create". Default: 1
  DO_INSTALL           Run "forge install --upgrade". Default: 1
  DO_STATUS            Print final Forge status commands. Default: 1

Examples:
  npm run forge:demo

  TAG=q3-allinone-demo-20260514 \
  SITE=a9data.atlassian.net \
  PRODUCT=Jira \
  npm run forge:demo
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

manifest_scalar() {
  local key="$1"
  awk -F': ' -v key="$key" '$1 == key {print $2; exit}' manifest.yml
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd docker
require_cmd forge

if [[ ! -f manifest.yml ]]; then
  echo "Run this script from the repo root." >&2
  exit 1
fi

RAW_APP_ID="${APP_ID:-$(manifest_scalar "id")}"
RAW_APP_ID="${RAW_APP_ID##*/}"
APP_ID="${RAW_APP_ID}"

if [[ -z "${APP_ID}" ]]; then
  echo "Unable to determine APP_ID. Set APP_ID explicitly." >&2
  exit 1
fi

CONTAINER_KEY="${CONTAINER_KEY:-quake3-allinone}"
ENVIRONMENT="${ENVIRONMENT:-development}"
SITE="${SITE:-a9data.atlassian.net}"
PRODUCT="${PRODUCT:-Jira}"
IMAGE_NAME="${IMAGE_NAME:-forge-q3-allinone}"
SERVICE_DIR="${SERVICE_DIR:-./services/quake3-allinone}"
PLATFORM="${PLATFORM:-linux/amd64}"
DO_CREATE_CONTAINER="${DO_CREATE_CONTAINER:-1}"
DO_INSTALL="${DO_INSTALL:-1}"
DO_STATUS="${DO_STATUS:-1}"
TAG="${TAG:-q3-allinone-demo-$(date -u '+%Y%m%d%H%M%S')}"

if [[ ! "$APP_ID" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "APP_ID must be a Forge app UUID, got: $APP_ID" >&2
  exit 1
fi

FORGE_IMAGE="forge-ecr.services.atlassian.com/forge/${APP_ID}/${CONTAINER_KEY}"
LOCAL_IMAGE="${IMAGE_NAME}:${TAG}"

export APP_ID TAG

log "Forge demo target"
printf 'App ID:        %s\n' "${APP_ID}"
printf 'Container key: %s\n' "${CONTAINER_KEY}"
printf 'Environment:   %s\n' "${ENVIRONMENT}"
printf 'Site:          %s\n' "${SITE}"
printf 'Product:       %s\n' "${PRODUCT}"
printf 'Image tag:     %s\n' "${TAG}"
printf 'Forge image:   %s:%s\n' "${FORGE_IMAGE}" "${TAG}"

if [[ "${DO_CREATE_CONTAINER}" == "1" ]]; then
  log "Ensuring Forge container repository exists"
  if ! forge containers create -k "${CONTAINER_KEY}"; then
    echo "forge containers create did not succeed cleanly. Continuing in case the repository already exists." >&2
  fi
fi

log "Authenticating Docker to Forge container registry"
forge containers docker-login

log "Building ${LOCAL_IMAGE}"
docker build "${SERVICE_DIR}" \
  --platform "${PLATFORM}" \
  -t "${LOCAL_IMAGE}"

log "Tagging image for Forge registry"
docker tag "${LOCAL_IMAGE}" "${FORGE_IMAGE}:${TAG}"

log "Pushing ${FORGE_IMAGE}:${TAG}"
docker push "${FORGE_IMAGE}:${TAG}"

log "Deploying Forge app to ${ENVIRONMENT}"
forge deploy -e "${ENVIRONMENT}" --non-interactive

if [[ "${DO_INSTALL}" == "1" ]]; then
  log "Upgrading installation on ${SITE} (${PRODUCT})"
  forge install \
    --upgrade \
    --site "${SITE}" \
    --product "${PRODUCT}" \
    --environment "${ENVIRONMENT}" \
    --confirm-scopes \
    --non-interactive
fi

if [[ "${DO_STATUS}" == "1" ]]; then
  log "Follow-up checks"
  printf 'forge show services -e %s -s q3-relay\n' "${ENVIRONMENT}"
  printf 'forge install list -e %s\n' "${ENVIRONMENT}"
  printf 'bash scripts/q3-relay-admin.sh status-all\n'
fi
