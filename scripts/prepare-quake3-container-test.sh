#!/usr/bin/env bash
set -euo pipefail

CONTAINER_KEY="${CONTAINER_KEY:-quake3-allinone}"
SERVICE_DIR="${SERVICE_DIR:-./services/quake3-allinone}"
TAG="${TAG:-q3-allinone-test-20260421}"
ENVIRONMENT="${ENVIRONMENT:-development}"
APP_ID="${APP_ID:-0fc32483-5342-46c9-9c21-2d5b6c68a963}"
REPO_URI="${REPO_URI:-}"
DO_CREATE_CONTAINER="${DO_CREATE_CONTAINER:-1}"
DO_PUSH="${DO_PUSH:-1}"
DO_DEPLOY="${DO_DEPLOY:-1}"

usage() {
  cat <<EOF
Usage:
  APP_ID=<registered-app-uuid> [REPO_URI=<forge-repo-uri>] $0

Environment:
  APP_ID               Registered Forge app UUID. Required.
  REPO_URI             Container repo URI. Optional; defaults to README pattern.
  TAG                  Image tag. Default: ${TAG}
  CONTAINER_KEY        Forge container key. Default: ${CONTAINER_KEY}
  ENVIRONMENT          Forge environment. Default: ${ENVIRONMENT}
  DO_CREATE_CONTAINER  Run forge containers create. Default: ${DO_CREATE_CONTAINER}
  DO_PUSH              Push image to Forge registry. Default: ${DO_PUSH}
  DO_DEPLOY            Run forge deploy. Default: ${DO_DEPLOY}
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f manifest.yml ]]; then
  echo "Run this script from the forge-containers-app root." >&2
  exit 1
fi

if [[ -z "$APP_ID" ]]; then
  echo "APP_ID is required. Use the UUID from the already-registered Forge app." >&2
  usage >&2
  exit 1
fi

if [[ "$APP_ID" == ari:* ]]; then
  APP_ID="${APP_ID##*/}"
fi

if [[ ! "$APP_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-4[0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$ ]]; then
  echo "APP_ID must be a Forge app UUID, got: $APP_ID" >&2
  exit 1
fi

if [[ -z "$REPO_URI" ]]; then
  REPO_URI="forge-ecr.services.atlassian.com/forge/${APP_ID}/${CONTAINER_KEY}"
fi

echo "Forge Containers EAP request details:"
echo "  App ID:        $APP_ID"
echo "  Container key: $CONTAINER_KEY"
echo "  EAP request:   https://ecosystem.atlassian.net/wiki/spaces/IC/pages/4342251535/Forge+Containers+-+EAP+Registration"
echo

export APP_ID TAG

if [[ "$DO_CREATE_CONTAINER" == "1" ]]; then
  echo "Creating container repository if it does not already exist..."
  if ! forge containers create -k "$CONTAINER_KEY"; then
    echo "forge containers create failed. If the container already exists, continuing." >&2
  fi
fi

echo "Authenticating Docker to Forge container registry..."
forge containers docker-login

echo "Building image: ${REPO_URI}:${TAG}"
docker build "$SERVICE_DIR" \
  --platform linux/amd64 \
  -t "${REPO_URI}:${TAG}"

if [[ "$DO_PUSH" == "1" ]]; then
  echo "Pushing image: ${REPO_URI}:${TAG}"
  docker push "${REPO_URI}:${TAG}"
fi

if [[ "$DO_DEPLOY" == "1" ]]; then
  echo "Deploying Forge app to ${ENVIRONMENT}..."
  forge deploy -e "$ENVIRONMENT"
fi

cat <<EOF

Next checks:
  forge show containers -e ${ENVIRONMENT}
  forge show services -e ${ENVIRONMENT}
  forge webtrigger -e ${ENVIRONMENT}

When forge webtrigger prints the q3-relay-health-trigger URL, call:
  curl -sS '<WEB_TRIGGER_URL>'
EOF
