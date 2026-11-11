#!/bin/sh
# 00-preflight.sh: read-only Azure checks before creating anything
set -eu

# shellcheck source=infra/config.sh
. "$(dirname "$0")/config.sh"

fail=0
ok()   { printf '  [OK]   %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=1; }

echo "== Preflight for region: $LOCATION"

echo "-- 1. Azure login / subscription"
if ! az account show >/dev/null 2>&1; then
  bad "Not logged in. Run: az login"
  exit 1
fi
sub_name=$(az account show --query name -o tsv)
sub_state=$(az account show --query state -o tsv)
if [ "$sub_state" = "Enabled" ]; then ok "Subscription '$sub_name' is $sub_state"; else bad "Subscription '$sub_name' is $sub_state"; fi

echo "-- 2. Region policy (Azure for Students restricts locations)"
allowed=$(az policy assignment list \
  --query "[].parameters.listOfAllowedLocations.value[]" -o tsv 2>/dev/null || true)
if [ -z "$allowed" ]; then
  ok "No allowed-locations policy found"
elif printf '%s\n' "$allowed" | grep -qx "$LOCATION"; then
  ok "$LOCATION is in the allowed-locations policy"
else
  bad "$LOCATION is NOT allowed by policy. Allowed regions: $(printf '%s ' "$allowed")"
fi

echo "-- 3. Resource providers"
for ns in Microsoft.Compute Microsoft.Network; do
  state=$(az provider show -n "$ns" --query registrationState -o tsv 2>/dev/null || echo unknown)
  if [ "$state" = "Registered" ]; then ok "$ns $state"; else bad "$ns is $state (run: az provider register -n $ns)"; fi
done

echo "-- 4. vCPU quota (need $VCPU_NEEDED)"
usage=$(az vm list-usage -l "$LOCATION" --query "[].[localName, currentValue, limit]" -o tsv)
tab=$(printf '\t')
for name in "Total Regional vCPUs" "$QUOTA_FAMILY"; do
  line=$(printf '%s\n' "$usage" | grep "^$name$tab" || true)
  if [ -z "$line" ]; then bad "$name: quota not found"; continue; fi
  used=$(printf '%s' "$line" | cut -f2); limit=$(printf '%s' "$line" | cut -f3)
  free=$((limit - used))
  if [ "$free" -ge "$VCPU_NEEDED" ]; then
    ok "$name: $used used / $limit limit ($free free)"
  else
    bad "$name: $used used / $limit limit ($free free, need $VCPU_NEEDED)"
  fi
done

echo "-- 5. Public IP quota (need $PUBLIC_IPS_NEEDED)"
pip=$(az network list-usages -l "$LOCATION" \
  --query "[?name.value=='PublicIPAddresses'].[currentValue, limit]" -o tsv)
used=$(printf '%s' "$pip" | cut -f1); limit=$(printf '%s' "$pip" | cut -f2)
if [ -n "$used" ] && [ $((limit - used)) -ge "$PUBLIC_IPS_NEEDED" ]; then
  ok "Public IPs: $used used / $limit limit"
else
  bad "Public IPs: '${used:-?}' used / '${limit:-?}' limit (need $PUBLIC_IPS_NEEDED free)"
fi

echo "-- 6. VM sizes offered without restriction"
# One list-skus call (it is slow), then check each size against the result
offered=$(az vm list-skus -l "$LOCATION" --resource-type virtualMachines --size Standard_B2 \
  --query "[?length(restrictions)==\`0\`].name" -o tsv)
for size in $(printf '%s\n' "$VM1_SIZE" "$VM2_SIZE" "$VM3_SIZE" | sort -u); do
  if printf '%s\n' "$offered" | grep -qx "$size"; then ok "$size available"; else bad "$size not available in $LOCATION"; fi
done

echo "-- 7. Ubuntu 22.04 LTS image"
if ver=$(az vm image show --urn "$IMAGE_URN" -l "$LOCATION" --query name -o tsv 2>/dev/null); then
  ok "Ubuntu 22.04 LTS gen2 image available (version $ver)"
else
  bad "Image $IMAGE_URN not found in $LOCATION"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PREFLIGHT PASSED for $LOCATION"
else
  echo "PREFLIGHT FAILED — fix the [FAIL] items above before creating resources"
  exit 1
fi
