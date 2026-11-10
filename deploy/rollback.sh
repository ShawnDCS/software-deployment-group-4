#!/bin/sh
# rollback.sh — manual instant rollback on VM3: restart the previous colour's (stopped)
# container, health-check it, switch Nginx back, update the state file.
# Usage (on VM3 as deploy):  sh rollback.sh      or from a laptop:
#   cat deploy/lib.sh deploy/rollback.sh | ssh -F infra/ssh_config g4-prod sudo -u deploy sh -s
set -eu
# shellcheck source=deploy/lib.sh
command -v wait_healthy >/dev/null 2>&1 || . "$(dirname "$0")/lib.sh"
DRAIN_SECONDS=${DRAIN_SECONDS:-10}

CUR=$(current_color)
[ "$CUR" != none ] || { log "No deployment recorded; nothing to roll back"; exit 1; }
PREV=$(other_color "$CUR")
PREV_BUILD=$(jq -r '.previous_build // ""' "$STATE_FILE")
CUR_BUILD=$(jq -r '.build' "$STATE_FILE")
docker inspect "guessgame-$PREV" >/dev/null 2>&1 || { log "No guessgame-$PREV container to roll back to"; exit 1; }

log "Rolling back: $CUR (build $CUR_BUILD) -> $PREV (build ${PREV_BUILD:-?})"
docker start "guessgame-$PREV" >/dev/null
wait_healthy "http://127.0.0.1:$(port_of "$PREV")/health" 12 5
switch_upstream "$PREV" "${PREV_BUILD:-unknown}"
commit=$(docker inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "guessgame-$PREV" | cut -c1-7)
write_state "$PREV" "${PREV_BUILD:-unknown}" "${commit:-unknown}" "$CUR" "$CUR_BUILD"
annotate "Manual rollback to build ${PREV_BUILD:-?} ($PREV)" rollback "$PREV"
sleep "$DRAIN_SECONDS"
docker stop -t 10 "guessgame-$CUR" >/dev/null
log "Rollback complete: $(cat "$STATE_FILE")"
