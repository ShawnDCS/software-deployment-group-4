#!/bin/sh
# 03-bootstrap-target.sh — runs ON VM2 (test) and VM3 (prod) as root.
# Creates the `deploy` user Jenkins logs in as, and the app data / deploy-state directories.
# Usage on the VM: sh 03-bootstrap-target.sh
set -eu

# Fixed UID 1100 so it never collides with the container's appuser (UID 1001).
if ! id deploy >/dev/null 2>&1; then
  groupadd -g 1100 deploy
  useradd --create-home --shell /bin/bash -u 1100 -g 1100 deploy
elif [ "$(id -u deploy)" != 1100 ]; then
  groupmod -g 1100 deploy
  usermod -u 1100 deploy
  chown -R deploy:deploy /home/deploy
fi
# docker group lets deploy run containers without sudo. Note for Q&A: docker group access is
# effectively root on that host, which is why only Jenkins' key can log in as deploy.
usermod -aG docker deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

# Best-score volume: owned by the container's appuser (fixed UID/GID 1001).
install -d -m 755 -o 1001 -g 1001 /var/lib/app-data
# Deploy state (current-release JSON), written by the deploy scripts.
install -d -m 755 -o deploy -g deploy /var/lib/app-deploy

echo "host=$(hostname) deploy-user=$(id deploy) app-data=$(stat -c '%u:%g' /var/lib/app-data)"
