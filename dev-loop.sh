#!/bin/bash
set -e pipefail

# Cleanup function to stop containers
cleanup() {
    echo "Stopping containers..."
    docker compose down
    exit 0
}

# Trap signals to run cleanup
trap cleanup SIGINT SIGTERM EXIT

# Set environment variables
export APP_ID=<ADD YOUR APP_ID HERE>
export ENV_ID=<ADD YOUR ENV_ID HERE>
export TAG=latest

# Download the platform side-car
forge containers docker-login
docker pull forge-ecr.services.atlassian.com/forge-platform/proxy-sidecar:latest

docker compose up --build -d

forge tunnel