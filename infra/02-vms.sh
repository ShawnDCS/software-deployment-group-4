#!/bin/sh
# 02-vms.sh — creates the three Ubuntu 22.04 VMs with static private IPs.
#   VM1 Jenkins (public IP + DNS name), VM2 test (NO public IP), VM3 prod (public IP + DNS name)
# Cost (koreacentral, Linux pay-as-you-go): B2als_v2 $0.0468/h + 2 x B2ats_v2 $0.0117/h = ~$0.07/h
# while running, plus ~$2.40/month per Standard SSD disk and ~$3.65/month per public IP.
# Every VM gets a nightly auto-shutdown (deallocate) at $AUTO_SHUTDOWN_UTC UTC to save credit.
set -eu
# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"

if [ ! -f "$SSH_KEY" ]; then
  echo "== Generating admin SSH key $SSH_KEY (private key stays on this laptop)"
  ssh-keygen -q -t ed25519 -N "" -C "swe40006-g4-admin" -f "$SSH_KEY"
fi

# create_vm NAME SIZE PRIVATE_IP NSG DNS_LABEL   (DNS_LABEL "-" = no public IP)
create_vm() {
  name=$1; size=$2; ip=$3; nsg=$4; dns=$5
  if az vm show -g "$RESOURCE_GROUP" -n "$name" -o none 2>/dev/null; then
    echo "== $name already exists, skipping create"
  else
    echo "== Creating $name ($size, $ip)"
    if [ "$dns" = "-" ]; then
      set -- --public-ip-address ""
    else
      set -- --public-ip-address "pip-$name" --public-ip-sku Standard --public-ip-address-dns-name "$dns"
    fi
    az vm create -g "$RESOURCE_GROUP" -n "$name" -l "$LOCATION" \
      --image "$IMAGE_URN" --size "$size" \
      --admin-username "$ADMIN_USER" --ssh-key-values "$SSH_KEY.pub" --authentication-type ssh \
      --vnet-name "$VNET_NAME" --subnet "$SUBNET_NAME" --private-ip-address "$ip" --nsg "$nsg" \
      --storage-sku StandardSSD_LRS --os-disk-size-gb 30 \
      --nic-delete-option Delete --os-disk-delete-option Delete \
      --tags project=swe40006 group=4 role="$name" \
      "$@" \
      --query "{name:'$name', privateIp:privateIpAddress, publicIp:publicIpAddress, fqdn:fqdns}" -o table
  fi
  az vm auto-shutdown -g "$RESOURCE_GROUP" -n "$name" --time "$AUTO_SHUTDOWN_UTC" -o none
  echo "   auto-shutdown at $AUTO_SHUTDOWN_UTC UTC"
}

create_vm "$VM1_NAME" "$VM1_SIZE" "$VM1_IP" nsg-vm1-jenkins swe40006-g4-jenkins
create_vm "$VM2_NAME" "$VM2_SIZE" "$VM2_IP" nsg-vm2-test    -
create_vm "$VM3_NAME" "$VM3_SIZE" "$VM3_IP" nsg-vm3-prod    swe40006-g4-game

echo "== Summary"
az vm list -g "$RESOURCE_GROUP" -d \
  --query "[].{name:name, size:hardwareProfile.vmSize, privateIp:privateIps, publicIp:publicIps, fqdn:fqdns, power:powerState}" -o table
