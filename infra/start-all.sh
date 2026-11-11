#!/bin/sh
# start-all.sh: start all three VMs
set -eu
# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"
ids=$(az vm list -g "$RESOURCE_GROUP" --query "[].id" -o tsv)
# shellcheck disable=SC2086
az vm start --ids $ids -o none
az vm list -g "$RESOURCE_GROUP" -d --query "[].{name:name, power:powerState, publicIp:publicIps, fqdn:fqdns}" -o table
