#!/bin/sh
# 03-bootstrap.sh — pushes the bootstrap scripts to all VMs with `az vm run-command invoke`.
# run-command goes through the Azure agent, so it works on VM2 even though VM2 has no public IP.
set -eu
# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"
DIR=$(dirname "$0")

# run VM SCRIPT ARGS...
run() {
  vm=$1; script=$2; shift 2
  [ $# -gt 0 ] && set -- --parameters "$@"
  az vm run-command invoke -g "$RESOURCE_GROUP" -n "$vm" --command-id RunShellScript \
    --scripts @"$script" "$@" \
    --query "value[0].message" -o tsv | sed "s/^/[$vm] /"
}

echo "== Common bootstrap (Docker, swap, timezone) on all VMs in parallel"
run "$VM1_NAME" "$DIR/03-bootstrap-common.sh" "$ADMIN_USER" 2 &
run "$VM2_NAME" "$DIR/03-bootstrap-common.sh" "$ADMIN_USER" 2 &
run "$VM3_NAME" "$DIR/03-bootstrap-common.sh" "$ADMIN_USER" 2 &
wait

echo "== Deploy user + data dirs on test and prod"
run "$VM2_NAME" "$DIR/03-bootstrap-target.sh" &
run "$VM3_NAME" "$DIR/03-bootstrap-target.sh" &
wait
