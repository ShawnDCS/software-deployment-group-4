#!/bin/sh
# start-all.sh — start all 3 VMs. Jenkins and app containers restart automatically (restart policies).
set -eu
# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"
ids=$(az vm list -g "$RESOURCE_GROUP" --query "[].id" -o tsv)
# shellcheck disable=SC2086  # one argument per VM id is intended
az vm start --ids $ids -o none
az vm list -g "$RESOURCE_GROUP" -d --query "[].{name:name, power:powerState, publicIp:publicIps, fqdn:fqdns}" -o table
