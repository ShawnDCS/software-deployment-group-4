#!/bin/sh
# 03-bootstrap-target.sh: deploy user and data folders on test and prod
set -eu

# Fixed UID 1100 so it never collides with the container's appuser (UID 1001)
if ! id deploy >/dev/null 2>&1; then
  groupadd -g 1100 deploy
  useradd --create-home --shell /bin/bash -u 1100 -g 1100 deploy
elif [ "$(id -u deploy)" != 1100 ]; then
  groupmod -g 1100 deploy
  usermod -u 1100 deploy
  chown -R deploy:deploy /home/deploy
fi
usermod -aG docker deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

# Best-score volume
install -d -m 755 -o 1001 -g 1001 /var/lib/app-data
# Deploy state (current-release JSON), written by the deploy scripts
install -d -m 755 -o deploy -g deploy /var/lib/app-deploy

echo "host=$(hostname) deploy-user=$(id deploy) app-data=$(stat -c '%u:%g' /var/lib/app-data)"
