#!/bin/sh
# deploy-prod.sh IMAGE BUILD COMMIT: blue-green deploy on VM3
set -eu
# shellcheck source=deploy/lib.sh
command -v wait_healthy >/dev/null 2>&1 || . "$(dirname "$0")/lib.sh"

IMAGE=${1:?usage: deploy-prod.sh IMAGE BUILD COMMIT}
BUILD=${2:?build}
COMMIT=${3:?commit}
DRAIN_SECONDS=${DRAIN_SECONDS:-60}

OLD=$(current_color)
OLD_BUILD=$(jq -r '.build // ""' "$STATE_FILE" 2>/dev/null || true)
NEW=$(other_color "$OLD")
PORT=$(port_of "$NEW")
log "Live colour: $OLD (build ${OLD_BUILD:-none}). Starting $NEW container with build $BUILD..."

if ! docker pull -q "$IMAGE"; then
  docker image inspect "$IMAGE" >/dev/null 2>&1 || { log "Cannot pull $IMAGE and no local copy; production unchanged"; exit 1; }
  log "Pull failed; using the local copy of $IMAGE"
fi
docker rm -f "guessgame-$NEW" >/dev/null 2>&1 || true
docker run -d --name "guessgame-$NEW" --hostname "prod-$NEW" --restart unless-stopped \
  -p "127.0.0.1:$PORT:3000" \
  -v /var/lib/app-data:/app/data \
  -e DEPLOY_COLOR="$NEW" \
  --memory 200m \
  "$IMAGE" >/dev/null

if ! wait_healthy "http://127.0.0.1:$PORT/health" 12 5; then
  docker logs --tail 30 "guessgame-$NEW" 2>&1 | sed 's/^/    | /' || true
  docker rm -f "guessgame-$NEW" >/dev/null 2>&1 || true
  annotate "ROLLBACK: build $BUILD failed health check, production stays on $OLD (build ${OLD_BUILD:-none})" rollback "build-$BUILD"
  log "ROLLBACK: build $BUILD never became healthy. Nginx untouched; production still serves $OLD (build ${OLD_BUILD:-none})."
  exit 1
fi

switch_upstream "$NEW" "$BUILD" || { docker rm -f "guessgame-$NEW" >/dev/null 2>&1; exit 1; }

# Confirm Nginx really serves the new build before declaring success
served=""
for _ in 1 2 3 4 5 6; do
  if curl -fs -m 3 http://127.0.0.1/ | grep -q "Build #$BUILD<"; then served=yes; break; fi
  sleep 1
done
if [ -z "$served" ]; then
  log "Nginx is not serving build $BUILD; switching back to $OLD"
  if [ "$OLD" != none ]; then switch_upstream "$OLD" "$OLD_BUILD" || true; fi
  docker rm -f "guessgame-$NEW" >/dev/null 2>&1 || true
  exit 1
fi

write_state "$NEW" "$BUILD" "$COMMIT" "$OLD" "$OLD_BUILD"
annotate "Deployed build $BUILD ($COMMIT) to $NEW" "$NEW" "build-$BUILD"
log "Production now on $NEW: $(cat "$STATE_FILE")"

if [ "$OLD" != none ] && docker inspect "guessgame-$OLD" >/dev/null 2>&1; then
  log "Draining $OLD for ${DRAIN_SECONDS}s before stopping it (kept for instant rollback)"
  sleep "$DRAIN_SECONDS"
  docker stop -t 10 "guessgame-$OLD" >/dev/null
  log "Stopped guessgame-$OLD"
fi
prune_images
