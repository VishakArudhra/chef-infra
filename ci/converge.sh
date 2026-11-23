#!/usr/bin/env bash
# Run cinc-client NOW on every node of a policy group (instead of waiting for
# the 30-minute timer). Usage: DEPLOY_KEY=~/key ci/converge.sh dev
. "$(dirname "$0")/lib.sh"
GROUP="${1:?usage: converge.sh <policy_group>}"
require_deploy_key

NODES="$(nodes_in_group "$GROUP")"
if [ -z "$NODES" ]; then
  echo "No nodes found in policy group '$GROUP' - did you bootstrap them?" >&2
  exit 1
fi
echo ">> Converging policy group '$GROUP': $(echo $NODES)"

LOG="$(mktemp)"
# -a hostname: connect using the node's hostname (app01...), resolved via /etc/hosts.
knife ssh "policy_group:${GROUP} AND policy_name:${POLICY_NAME}" \
  "sudo cinc-client --no-color" \
  -c "$KNIFE_CFG" -x "$DEPLOY_USER" -i "$DEPLOY_KEY" -a hostname \
  --no-host-key-verify | tee "$LOG"

# knife ssh doesn't always return non-zero when one node fails, so check the output too.
if grep -Eq "FATAL:|Cinc Client failed|Chef Infra Client failed|exited with status [1-9]" "$LOG"; then
  echo ">> cinc-client FAILED on at least one node in '$GROUP' (see output above)" >&2
  exit 1
fi
echo ">> Converge of '$GROUP' OK"
