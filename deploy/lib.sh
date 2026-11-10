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

# ---- production (VM3) helpers ----
STATE_FILE=/var/lib/app-deploy/current-release
UPSTREAM_FILE=/etc/nginx/conf.d/guessgame-upstream.conf
UPSTREAM_TEMPLATE=/etc/nginx/guessgame-upstream.conf.template

port_of() { if [ "$1" = green ]; then echo 3002; else echo 3001; fi; }
other_color() { if [ "$1" = blue ]; then echo green; else echo blue; fi; }

# current_color — colour Nginx is serving now (from the state file), or "none" on first deploy.
current_color() {
  if [ -f "$STATE_FILE" ]; then jq -r '.color // "none"' "$STATE_FILE"; else echo none; fi
}

# switch_upstream COLOR BUILD — rewrite the whole upstream file, test, reload.
# If the new config fails `nginx -t`, the previous file is restored and Nginx is never reloaded.
switch_upstream() {
  color=$1; build=$2; port=$(port_of "$color")
  previous=$(cat "$UPSTREAM_FILE")
  sed "s/__COLOR__/$color/; s/__BUILD__/$build/; s/__PORT__/$port/" "$UPSTREAM_TEMPLATE" \
    | sudo /usr/bin/tee "$UPSTREAM_FILE" >/dev/null
  if ! sudo /usr/sbin/nginx -t >/dev/null 2>&1; then
    printf '%s\n' "$previous" | sudo /usr/bin/tee "$UPSTREAM_FILE" >/dev/null
    log "nginx -t FAILED for $color; previous upstream restored"
    return 1
  fi
  sudo /usr/sbin/nginx -s reload
  log "Switching Nginx to $color (127.0.0.1:$port)... Reload complete."
}

# write_state COLOR BUILD COMMIT PREV_COLOR PREV_BUILD
write_state() {
  jq -cn --arg color "$1" --arg build "$2" --arg commit "$3" --arg pc "$4" --arg pb "$5" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{color:$color, build:$build, commit:$commit, deployed_at:$at, previous_color:$pc, previous_build:$pb}' \
    > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# annotate TEXT TAG... — Grafana annotation (best effort; a Grafana problem never fails a deploy).
annotate() {
  text=$1; shift
  pw=$(sed -n 's/^GRAFANA_ADMIN_PASSWORD=//p' /opt/monitoring/.env 2>/dev/null || true)
  [ -n "$pw" ] || { log "Grafana annotation skipped (no credentials)"; return 0; }
  tags=$(printf '"%s",' deploy "$@"); tags="[${tags%,}]"
  if curl -fs -m 5 -u "admin:$pw" -H 'Content-Type: application/json' \
       -d "{\"text\":\"$text\",\"tags\":$tags}" http://127.0.0.1:3030/grafana/api/annotations >/dev/null; then
    log "Grafana annotation added: $text"
  else
    log "Grafana annotation failed (ignored)"
  fi
}
