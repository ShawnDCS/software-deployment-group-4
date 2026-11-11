#!/bin/sh
# 01-network.sh: resource group, VNet, subnet and one NSG per VM
set -eu
# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"

echo "== Resource group $RESOURCE_GROUP ($LOCATION)"
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" --tags project=swe40006 group=4 -o table

echo "== VNet $VNET_NAME $VNET_PREFIX / subnet $SUBNET_NAME $SUBNET_PREFIX"
az network vnet create -g "$RESOURCE_GROUP" -n "$VNET_NAME" --address-prefixes "$VNET_PREFIX" \
  --subnet-name "$SUBNET_NAME" --subnet-prefixes "$SUBNET_PREFIX" -o table
# New Azure VNets are private by default (no outbound internet for VMs without a public IP)
az network vnet subnet update -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" -n "$SUBNET_NAME" \
  --default-outbound-access true --query "{subnet:name, defaultOutboundAccess:defaultOutboundAccess}" -o table

# GitHub publishes the IP ranges its webhooks come from
GITHUB_HOOK_IPS=$(gh api meta --jq '.hooks[]' | grep -v ':' | tr '\n' ' ')
echo "GitHub webhook ranges: $GITHUB_HOOK_IPS"

nsg() { az network nsg create -g "$RESOURCE_GROUP" -n "$1" -o none; echo "created NSG $1"; }
# rule NSG NAME PRIORITY PORT SOURCES
rule() {
  n=$1; name=$2; prio=$3; port=$4; shift 4
  az network nsg rule create -g "$RESOURCE_GROUP" --nsg-name "$n" -n "$name" --priority "$prio" \
    --direction Inbound --access Allow --protocol Tcp --destination-port-ranges "$port" \
    --source-address-prefixes "$@" -o none
  echo "  rule $name: tcp/$port from $*"
}

nsg nsg-vm1-jenkins
# shellcheck disable=SC2086
rule nsg-vm1-jenkins Allow-SSH-Team        100 22   $TEAM_IPS
# shellcheck disable=SC2086
rule nsg-vm1-jenkins Allow-Jenkins-Team    110 8080 $TEAM_IPS
# shellcheck disable=SC2086
rule nsg-vm1-jenkins Allow-Jenkins-GitHub  120 8080 $GITHUB_HOOK_IPS

nsg nsg-vm2-test

nsg nsg-vm3-prod
# shellcheck disable=SC2086
rule nsg-vm3-prod Allow-SSH-Team           100 22   $TEAM_IPS
rule nsg-vm3-prod Allow-HTTP-Public        110 80   Internet
rule nsg-vm3-prod Allow-Grafana-Public     120 3030 Internet
rule nsg-vm3-prod Allow-HTTPS-Public       130 443  Internet

echo "== Summary"
az network nsg list -g "$RESOURCE_GROUP" --query "[].{nsg:name, rules:length(securityRules)}" -o table
