# Shared helpers for the CI scripts. Source it: . "$(dirname "$0")/lib.sh"
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNIFE_CFG="${KNIFE_CFG:-$REPO_ROOT/.chef/config.rb}"
POLICY_NAME="${POLICY_NAME:-myapp}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"

# Node names (app01, app02...) in a policy group, one per line.
nodes_in_group() {
  knife search node "policy_group:$1 AND policy_name:${POLICY_NAME}" -i -c "$KNIFE_CFG" 2>/dev/null \
    | grep -v 'items found' | sed '/^[[:space:]]*$/d' || true
}

require_deploy_key() {
  if [ -z "${DEPLOY_KEY:-}" ] || [ ! -f "$DEPLOY_KEY" ]; then
    echo "DEPLOY_KEY must point to the deploy user's private key" >&2
    exit 2
  fi
}
