#!/bin/sh
# deploy-prod.sh IMAGE BUILD COMMIT — runs on VM3 (prod) as `deploy`.
# Level 3 version: simple stop-and-replace of the single production container behind Nginx.
# (Upgraded to blue-green with rollback in Phase 5.)
set -eu
# shellcheck source=deploy/lib.sh
command -v wait_healthy >/dev/null 2>&1 || . "$(dirname "$0")/lib.sh"

IMAGE=${1:?usage: deploy-prod.sh IMAGE BUILD COMMIT}
BUILD=${2:?build}
COMMIT=${3:?commit}
COLOR=blue
PORT=3001
NAME=guessgame-$COLOR
STATE=/var/lib/app-deploy/current-release

log "Deploying $IMAGE (build $BUILD) to production as $COLOR"
docker pull -q "$IMAGE"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --hostname "prod-$COLOR" --restart unless-stopped \
  -p "127.0.0.1:$PORT:3000" \
  -v /var/lib/app-data:/app/data \
  -e DEPLOY_COLOR="$COLOR" \
  --memory 200m \
  "$IMAGE" >/dev/null

if ! wait_healthy "http://127.0.0.1:$PORT/health"; then
  docker logs --tail 50 "$NAME" || true
  exit 1
fi

sed "s/__COLOR__/$COLOR/; s/__BUILD__/$BUILD/; s/__PORT__/$PORT/" /etc/nginx/guessgame-upstream.conf.template \
  | sudo /usr/bin/tee /etc/nginx/conf.d/guessgame-upstream.conf >/dev/null
sudo /usr/sbin/nginx -t 2>/dev/null
sudo /usr/sbin/nginx -s reload
log "Nginx now routes to $COLOR (127.0.0.1:$PORT)"

printf '{"color":"%s","build":"%s","commit":"%s","deployed_at":"%s"}\n' \
  "$COLOR" "$BUILD" "$COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE"
prune_images
log "Production deploy OK: $(cat "$STATE")"
