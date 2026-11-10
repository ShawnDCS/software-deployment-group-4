#!/bin/sh
# stop-all.sh — deallocate all 3 VMs (compute billing stops; disks + public IPs still cost ~$0.50/day).
# Public IPs are Standard/static, so addresses and DNS names stay the same after restart.
set -eu
# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"
ids=$(az vm list -g "$RESOURCE_GROUP" --query "[].id" -o tsv)
# shellcheck disable=SC2086  # one argument per VM id is intended
az vm deallocate --ids $ids -o none
az vm list -g "$RESOURCE_GROUP" -d --query "[].{name:name, power:powerState}" -o table
