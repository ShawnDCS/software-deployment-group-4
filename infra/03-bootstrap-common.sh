#!/bin/sh
# 03-bootstrap-common.sh: Docker, swap and timezone (runs on each VM as root)
set -eu
ADMIN_USER=${1:-azureuser}
SWAP_GB=${2:-2}
export DEBIAN_FRONTEND=noninteractive

timedatectl set-timezone Asia/Kuala_Lumpur

if [ ! -f /swapfile ] && [ "$SWAP_GB" -gt 0 ]; then
  fallocate -l "${SWAP_GB}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
  sysctl -p /etc/sysctl.d/99-swappiness.conf >/dev/null
fi

if ! command -v docker >/dev/null 2>&1; then
  apt-get update -q >/dev/null
  apt-get install -y -q ca-certificates curl gnupg jq >/dev/null
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck source=/dev/null
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q >/dev/null
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
fi

# Rotate container logs so a chatty container can't fill the 30 GB disk
if [ ! -f /etc/docker/daemon.json ]; then
  printf '{\n  "log-driver": "json-file",\n  "log-opts": { "max-size": "10m", "max-file": "3" }\n}\n' > /etc/docker/daemon.json
  systemctl restart docker
fi
systemctl enable --now docker >/dev/null 2>&1
usermod -aG docker "$ADMIN_USER"

echo "host=$(hostname) docker=$(docker version --format '{{.Server.Version}}') compose=$(docker compose version --short) swap=$(swapon --show=SIZE --noheadings | tr -d ' ') tz=$(date +%Z)"
