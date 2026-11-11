#!/bin/sh
# 07-https.sh: Let's Encrypt certificate and HTTPS for the game
set -eu
# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SSHC="$ROOT/infra/ssh_config"
FQDN=$(az vm show -d -g "$RESOURCE_GROUP" -n "$VM3_NAME" --query fqdns -o tsv)

echo "== 1. NSG: allow 443 to VM3"
az network nsg rule create -g "$RESOURCE_GROUP" --nsg-name nsg-vm3-prod -n Allow-HTTPS-Public --priority 130 \
  --direction Inbound --access Allow --protocol Tcp --destination-port-ranges 443 \
  --source-address-prefixes Internet --query "{rule:name, port:destinationPortRange, from:sourceAddressPrefix}" -o tsv

echo "== 2. Nginx base config"
sh "$ROOT/infra/06-prod-nginx.sh" | grep -E 'running|successful'

echo "== 3. Certificate for $FQDN"
COPYFILE_DISABLE=1 tar --no-xattrs -C "$ROOT/nginx" -cf - guessgame-https.conf.template \
  | ssh -F "$SSHC" g4-prod 'tar -C /tmp -xf -'
ssh -F "$SSHC" g4-prod sudo sh -s "$FQDN" <<'REMOTE'
set -eu
FQDN=$1
if ! command -v certbot >/dev/null 2>&1; then
  snap install --classic certbot >/dev/null
  ln -sf /snap/bin/certbot /usr/bin/certbot
fi
if [ ! -f "/etc/letsencrypt/live/$FQDN/fullchain.pem" ]; then
  # No email registered on purpose (no personal data)
  certbot certonly --webroot -w /var/www/certbot -d "$FQDN" \
    --non-interactive --agree-tos --register-unsafely-without-email 2>&1 | grep -E 'Successfully|Certificate is saved|expires|error|Error' || true
fi
test -f "/etc/letsencrypt/live/$FQDN/fullchain.pem" || { echo "certificate NOT issued"; exit 1; }
install -d /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nnginx -t && nginx -s reload\n' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

echo "== 4. HTTPS server block"
sed "s/__FQDN__/$FQDN/g" /tmp/guessgame-https.conf.template > /etc/nginx/conf.d/guessgame-https.conf
rm -f /tmp/guessgame-https.conf.template
nginx -t 2>&1 | tail -1
nginx -s reload
certbot certificates 2>/dev/null | grep -E 'Domains|Expiry'
systemctl list-timers 'snap.certbot*' --no-pager | grep -c certbot | sed 's/^/renewal timers: /'
REMOTE

echo "== 5. Jenkins Verify stage -> https, Grafana links -> https"
ssh -F "$SSHC" g4-jenkins "sudo sed -i 's|^PROD_PUBLIC_URL=.*|PROD_PUBLIC_URL=https://$FQDN|' /opt/jenkins/.env && grep ^PROD_PUBLIC_URL /opt/jenkins/.env && cd /opt/jenkins && docker compose up -d --force-recreate 2>&1 | tail -1"
sh "$ROOT/infra/05-monitoring.sh" | grep -A1 'Grafana health'
