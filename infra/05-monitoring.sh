#!/bin/sh
# 05-monitoring.sh: deploy Prometheus, Grafana and exporters to VM3
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SSHC="$ROOT/infra/ssh_config"

echo "== Copy monitoring/ to VM3:/opt/monitoring"
# shellcheck disable=SC2016
ssh -F "$SSHC" g4-prod 'sudo install -d -o "$USER" -g "$USER" /opt/monitoring'
COPYFILE_DISABLE=1 tar --no-xattrs -C "$ROOT/monitoring" --exclude .env -cf - . | ssh -F "$SSHC" g4-prod 'tar -C /opt/monitoring -xf -'

echo "== Start the stack"
ssh -F "$SSHC" g4-prod sh -s <<'REMOTE'
set -eu
cd /opt/monitoring
if [ ! -f .env ]; then
  umask 027
  printf 'GRAFANA_ADMIN_PASSWORD=%s\n' "$(openssl rand -base64 18 | tr -d '/+=')" > .env
  sudo chgrp deploy .env
  echo ".env created (Grafana admin password generated on this VM)"
fi
docker compose pull -q
docker compose up -d --remove-orphans 2>&1 | grep -v -- '- Pull' | tail -6
REMOTE

echo "== Wait for Prometheus targets"
sleep 20
ssh -F "$SSHC" g4-prod 'curl -s localhost:9090/api/v1/targets | jq -r ".data.activeTargets[] | \"\(.labels.job)\t\(.health)\t\(.lastError)\""'
echo "== Grafana health"
ssh -F "$SSHC" g4-prod 'curl -s localhost:3030/api/health | jq -c .'
echo "== Container memory"
ssh -F "$SSHC" g4-prod 'docker stats --no-stream --format "{{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}"; free -m | head -3'
