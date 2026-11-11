#!/bin/sh
# deploy-test.sh IMAGE: replace the test container on VM2
set -eu
# shellcheck source=deploy/lib.sh
command -v wait_healthy >/dev/null 2>&1 || . "$(dirname "$0")/lib.sh"

IMAGE=${1:?usage: deploy-test.sh IMAGE}
NAME=guessgame-test

log "Deploying $IMAGE to $(hostname)"
docker pull -q "$IMAGE"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --hostname vm2-test --restart unless-stopped \
  -p 3000:3000 \
  -v /var/lib/app-data:/app/data \
  -e DEPLOY_COLOR=test \
  --memory 256m \
  "$IMAGE" >/dev/null

if ! wait_healthy http://127.0.0.1:3000/health; then
  docker logs --tail 50 "$NAME" || true
  exit 1
fi
prune_images
log "Test deploy OK: $(docker ps --filter name=$NAME --format '{{.Image}} {{.Status}}')"
