#!/bin/sh
# 04-jenkins.sh: install Jenkins on VM1 and give it SSH access to test and prod
set -eu
# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

VM1_FQDN=$(az vm show -d -g "$RESOURCE_GROUP" -n "$VM1_NAME" --query fqdns -o tsv)
VM3_FQDN=$(az vm show -d -g "$RESOURCE_GROUP" -n "$VM3_NAME" --query fqdns -o tsv)
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$HOME/.ssh/known_hosts_swe40006"

echo "== 1. Copy jenkins/ to $VM1_FQDN:/opt/jenkins"
# shellcheck disable=SC2016
$SSH "$ADMIN_USER@$VM1_FQDN" 'sudo install -d -o "$USER" -g "$USER" /opt/jenkins'
COPYFILE_DISABLE=1 tar --no-xattrs -C "$ROOT/jenkins" --exclude .env --exclude secrets -cf - . | $SSH "$ADMIN_USER@$VM1_FQDN" 'tar -C /opt/jenkins -xf -'

echo "== 2. Configure and start Jenkins on VM1"
# Values are expanded locally
$SSH "$ADMIN_USER@$VM1_FQDN" sh -s <<REMOTE
set -eu
cd /opt/jenkins
if [ ! -f .env ]; then
  umask 077
  cat > .env <<ENV
JENKINS_ADMIN_ID=admin
JENKINS_ADMIN_PASSWORD=\$(openssl rand -base64 18 | tr -d '/+=')
DOCKERHUB_USER=$DOCKERHUB_USER
DOCKERHUB_TOKEN=
DOCKER_GID=\$(getent group docker | cut -d: -f3)
JENKINS_URL=http://$VM1_FQDN:8080/
GITHUB_REPO_URL=https://github.com/$GITHUB_REPO
TEST_HOST=$VM2_IP
PROD_HOST=$VM3_IP
PROD_PUBLIC_URL=http://$VM3_FQDN
ENV
  echo ".env created (admin password generated on this VM)"
fi
# Deploy key
install -d -m 700 secrets
if [ ! -f secrets/deploy_ed25519 ]; then
  ssh-keygen -q -t ed25519 -N "" -C "jenkins-deploy@vm1" -f secrets/deploy_ed25519
fi
sudo chown 1000:1000 secrets/deploy_ed25519
sudo chmod 400 secrets/deploy_ed25519
# Jenkins home + known_hosts for VM2/VM3 so SSH uses strict host key checking (no MITM)
sudo install -d -o 1000 -g 1000 /var/jenkins_home /var/jenkins_home/.ssh
ssh-keyscan -t ed25519 $VM2_IP $VM3_IP 2>/dev/null | sudo tee /var/jenkins_home/.ssh/known_hosts >/dev/null
sudo chown 1000:1000 /var/jenkins_home/.ssh/known_hosts
echo "known_hosts entries: \$(sudo wc -l < /var/jenkins_home/.ssh/known_hosts)"
docker compose up -d --build 2>&1 | tail -3
REMOTE

echo "== 3. Authorise Jenkins' deploy key on VM2 and VM3"
PUBKEY=$($SSH "$ADMIN_USER@$VM1_FQDN" 'cat /opt/jenkins/secrets/deploy_ed25519.pub')
TMP=$(mktemp)
cat > "$TMP" <<KEY
#!/bin/sh
set -eu
grep -qxF '$PUBKEY' /home/deploy/.ssh/authorized_keys || echo '$PUBKEY' >> /home/deploy/.ssh/authorized_keys
echo "\$(hostname): \$(wc -l < /home/deploy/.ssh/authorized_keys) key(s) for deploy"
KEY
for vm in "$VM2_NAME" "$VM3_NAME"; do
  az vm run-command invoke -g "$RESOURCE_GROUP" -n "$vm" --command-id RunShellScript \
    --scripts @"$TMP" --query "value[0].message" -o tsv | grep 'key(s)'
done
rm -f "$TMP"

echo "== 4. Wait for Jenkins to answer"
i=0
until curl -fs -o /dev/null "http://$VM1_FQDN:8080/login"; do
  i=$((i + 1)); [ "$i" -gt 40 ] && { echo "Jenkins did not come up"; exit 1; }
  sleep 5
done
echo "Jenkins is up: http://$VM1_FQDN:8080/"
