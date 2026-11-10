#!/bin/sh
# lib.sh — shared helpers. Jenkins pipes this file + a deploy script over SSH:
#   cat deploy/lib.sh deploy/deploy-test.sh | ssh deploy@host sh -s -- ARGS
# so the target servers never need a copy of the repository.

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# wait_healthy URL [TRIES] [INTERVAL] — poll URL until it returns "OK" (default 12 x 5 s = 60 s).
wait_healthy() {
  url=$1; tries=${2:-12}; interval=${3:-5}; n=1
  while [ "$n" -le "$tries" ]; do
    if [ "$(curl -fs -m 3 "$url" 2>/dev/null || true)" = "OK" ]; then
      log "Health check passed ($url, attempt $n/$tries)"
      return 0
    fi
    log "Waiting for $url ($n/$tries)"
    n=$((n + 1))
    sleep "$interval"
  done
  log "Health check FAILED after $tries attempts: $url"
  return 1
}

# Remove guessgame images not used by any container (running OR stopped), to save disk.
prune_images() {
  docker image prune -af --filter "label=org.opencontainers.image.title=guessgame" >/dev/null 2>&1 || true
}
