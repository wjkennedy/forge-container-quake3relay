#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build the Quake 3 all-in-one image, then publish it to Forge and optionally
Docker Hub.

Usage:
  bash scripts/rebuild-and-publish.sh

Required environment:
  TAG                       Image tag to build and publish.

Optional environment:
  IMAGE_NAME                Local image name. Default: forge-q3-allinone
  DOCKERFILE                Dockerfile path.
                            Default: services/quake3-allinone/Dockerfile
  BUILD_CONTEXT             Docker build context.
                            Default: services/quake3-allinone
  PLATFORM                  Docker build platform. Default: linux/amd64

  FORGE_IMAGE               Full Forge registry image ref, for example:
                            123456789012.dkr.ecr.us-west-2.amazonaws.com/q3-relay
                            If set, the script tags and pushes to Forge.
  FORGE_LOGIN               Run "forge containers docker-login" before pushing
                            to Forge. Default: 1 when FORGE_IMAGE is set.
  DEPLOY_FORGE              Run "forge deploy" after pushing to Forge.
                            Default: 0
  FORGE_ENV                 Forge environment for deploy/show commands.
                            Default: development

  DOCKERHUB_IMAGE           Full Docker Hub image ref, for example:
                            myorg/forge-q3-allinone
                            If set, the script tags and pushes to Docker Hub.

Examples:
  TAG=q3-allinone-20260423 \
  FORGE_IMAGE=123456789012.dkr.ecr.us-west-2.amazonaws.com/q3-relay \
  DOCKERHUB_IMAGE=myorg/forge-q3-allinone \
  bash scripts/rebuild-and-publish.sh

  TAG=q3-allinone-20260423 \
  FORGE_IMAGE=123456789012.dkr.ecr.us-west-2.amazonaws.com/q3-relay \
  DEPLOY_FORGE=1 \
  bash scripts/rebuild-and-publish.sh
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

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

: "${TAG:?Set TAG, for example TAG=q3-allinone-20260423}"

IMAGE_NAME="${IMAGE_NAME:-forge-q3-allinone}"
DOCKERFILE="${DOCKERFILE:-services/quake3-allinone/Dockerfile}"
BUILD_CONTEXT="${BUILD_CONTEXT:-services/quake3-allinone}"
PLATFORM="${PLATFORM:-linux/amd64}"
FORGE_ENV="${FORGE_ENV:-development}"

LOCAL_IMAGE="${IMAGE_NAME}:${TAG}"
FORGE_LOGIN="${FORGE_LOGIN:-}"
DEPLOY_FORGE="${DEPLOY_FORGE:-0}"

require_cmd docker

if [[ -n "${FORGE_IMAGE:-}" || "${DEPLOY_FORGE}" == "1" || -n "${FORGE_LOGIN}" ]]; then
  require_cmd forge
fi

log "Building ${LOCAL_IMAGE} from ${DOCKERFILE}"
docker build \
  --platform "${PLATFORM}" \
  -f "${DOCKERFILE}" \
  -t "${LOCAL_IMAGE}" \
  "${BUILD_CONTEXT}"

if [[ -n "${FORGE_IMAGE:-}" ]]; then
  if [[ -z "${FORGE_LOGIN}" ]]; then
    FORGE_LOGIN=1
  fi

  if [[ "${FORGE_LOGIN}" == "1" ]]; then
    log "Running Forge container registry login"
    forge containers docker-login
  fi

  log "Tagging ${LOCAL_IMAGE} as ${FORGE_IMAGE}:${TAG}"
  docker tag "${LOCAL_IMAGE}" "${FORGE_IMAGE}:${TAG}"

  log "Pushing ${FORGE_IMAGE}:${TAG}"
  docker push "${FORGE_IMAGE}:${TAG}"
fi

if [[ -n "${DOCKERHUB_IMAGE:-}" ]]; then
  log "Tagging ${LOCAL_IMAGE} as ${DOCKERHUB_IMAGE}:${TAG}"
  docker tag "${LOCAL_IMAGE}" "${DOCKERHUB_IMAGE}:${TAG}"

  log "Pushing ${DOCKERHUB_IMAGE}:${TAG}"
  docker push "${DOCKERHUB_IMAGE}:${TAG}"
fi

if [[ "${DEPLOY_FORGE}" == "1" ]]; then
  log "Deploying Forge app to ${FORGE_ENV}"
  forge deploy -e "${FORGE_ENV}"
fi

log "Done"
if [[ -n "${FORGE_IMAGE:-}" ]]; then
  printf 'Forge image: %s:%s\n' "${FORGE_IMAGE}" "${TAG}"
fi
if [[ -n "${DOCKERHUB_IMAGE:-}" ]]; then
  printf 'Docker Hub image: %s:%s\n' "${DOCKERHUB_IMAGE}" "${TAG}"
fi
