#!/bin/sh
# 06-prod-nginx.sh — install Nginx (nginx.org stable, pinned) on VM3 and the narrow sudo rule
# that lets the `deploy` user switch the live upstream. Run from the laptop.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SSHC="$ROOT/infra/ssh_config"
NGINX_VERSION="1.30.6-1~jammy"

COPYFILE_DISABLE=1 tar --no-xattrs -C "$ROOT/nginx" -cf - . | ssh -F "$SSHC" g4-prod 'mkdir -p /tmp/nginx-src && tar -C /tmp/nginx-src -xf -'

ssh -F "$SSHC" g4-prod sudo sh -s "$NGINX_VERSION" <<'REMOTE'
set -eu
NGINX_VERSION=$1
export DEBIAN_FRONTEND=noninteractive
if ! dpkg -s nginx 2>/dev/null | grep -q "Version: $NGINX_VERSION"; then
  curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor --yes -o /usr/share/keyrings/nginx-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu jammy nginx" \
    > /etc/apt/sources.list.d/nginx.list
  printf 'Package: *\nPin: origin nginx.org\nPin-Priority: 900\n' > /etc/apt/preferences.d/99nginx
  apt-get update -q >/dev/null
  apt-get install -y -q "nginx=$NGINX_VERSION" >/dev/null
  apt-mark hold nginx >/dev/null
fi

rm -f /etc/nginx/conf.d/default.conf
install -m 644 /tmp/nginx-src/guessgame.conf /etc/nginx/conf.d/guessgame.conf
install -m 644 /tmp/nginx-src/guessgame-upstream.conf.template /etc/nginx/guessgame-upstream.conf.template
# Initial upstream: blue (port 3001). Only created if no deploy has written one yet.
if [ ! -f /etc/nginx/conf.d/guessgame-upstream.conf ]; then
  sed 's/__COLOR__/blue/; s/__BUILD__/none/; s/__PORT__/3001/' /etc/nginx/guessgame-upstream.conf.template \
    > /etc/nginx/conf.d/guessgame-upstream.conf
fi
rm -rf /tmp/nginx-src

# deploy may ONLY: test the config, reload, and overwrite the upstream file (via tee).
cat > /etc/sudoers.d/deploy-nginx <<'SUDO'
deploy ALL=(root) NOPASSWD: /usr/sbin/nginx -t, /usr/sbin/nginx -s reload, /usr/bin/tee /etc/nginx/conf.d/guessgame-upstream.conf
SUDO
chmod 440 /etc/sudoers.d/deploy-nginx
visudo -cf /etc/sudoers.d/deploy-nginx

nginx -t 2>&1 | tail -1
systemctl enable --now nginx >/dev/null 2>&1
nginx -s reload
echo "nginx $(nginx -v 2>&1 | cut -d/ -f2) running; upstream: $(grep -o 'server [^;]*' /etc/nginx/conf.d/guessgame-upstream.conf)"
echo "sudo rights for deploy:"; sudo -l -U deploy | tail -1
REMOTE
