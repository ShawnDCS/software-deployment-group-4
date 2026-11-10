#!/bin/sh
# jenkins-build.sh [wait-only] — trigger the guessgame job (or just wait for the next build),
# wait for it to finish, and print its console log. Runs the API calls ON VM1 so the
# admin password never leaves the server.  Usage: sh infra/jenkins-build.sh [wait]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ssh -F "$ROOT/infra/ssh_config" g4-jenkins sh -s "${1:-trigger}" <<'REMOTE'
set -eu
set -a; . /opt/jenkins/.env; set +a
J=http://localhost:8080; A="$JENKINS_ADMIN_ID:$JENKINS_ADMIN_PASSWORD"; C=$(mktemp)
N=$(curl -s -u "$A" "$J/job/guessgame/api/json" | jq .nextBuildNumber)
if [ "$1" = trigger ]; then
  CRUMB=$(curl -s -c "$C" -u "$A" "$J/crumbIssuer/api/json" | jq -r '.crumbRequestField + ":" + .crumb')
  curl -s -b "$C" -u "$A" -H "$CRUMB" -X POST "$J/job/guessgame/build" -o /dev/null
fi
r=""
for _ in $(seq 1 180); do
  r=$(curl -s -u "$A" "$J/job/guessgame/$N/api/json" 2>/dev/null | jq -r 'if .building then "RUNNING" else .result end' 2>/dev/null || true)
  [ -n "$r" ] && [ "$r" != RUNNING ] && break
  sleep 5
done
curl -s -u "$A" "$J/job/guessgame/$N/consoleText"
echo "BUILD #$N RESULT: $r"
rm -f "$C"
REMOTE
