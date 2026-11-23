#!/usr/bin/env bash
# Promote the cookbook policy to a group: gate -> push -> converge -> verify.
# Usage: DEPLOY_KEY=~/key ci/deploy_policy.sh <policy_group>
. "$(dirname "$0")/lib.sh"
GROUP="${1:?usage: deploy_policy.sh <policy_group>}"
cd "$REPO_ROOT"

knife ssl fetch -c "$KNIFE_CFG" >/dev/null 2>&1 || true

echo "=== 1. Dependency gate ==="
python3 ci/check_versions.py --lock policyfiles/myapp.lock.json \
  --approved approved-versions.json --group "$GROUP" --knife-config "$KNIFE_CFG"

echo "=== 2. Push policy lock to '$GROUP' ==="
cinc push "$GROUP" policyfiles/myapp.rb -c "$KNIFE_CFG"

echo "=== 3. Converge ==="
ci/converge.sh "$GROUP"

echo "=== 4. Verify ==="
ci/smoke.sh "$GROUP"
