#!/usr/bin/env bash
# Post-deploy verification with InSpec (cinc-auditor) over SSH against the REAL nodes.
# Usage: DEPLOY_KEY=~/key ci/smoke.sh <policy_group> [expected_version]
. "$(dirname "$0")/lib.sh"
GROUP="${1:?usage: smoke.sh <policy_group> [expected_version]}"
EXPECTED_VERSION="${2:-}"
require_deploy_key
mkdir -p "$REPO_ROOT/reports"

for NODE in $(nodes_in_group "$GROUP"); do
  echo ">> Waiting for myapp on $NODE to report healthy (Spring Boot needs ~20s to start)"
  ssh -i "$DEPLOY_KEY" -o StrictHostKeyChecking=accept-new "$DEPLOY_USER@$NODE" \
    'test -e /opt/myapp/current.jar || { echo "   no release on this node yet"; exit 0; }
     for i in $(seq 1 60); do curl -fs localhost:8080/actuator/health >/dev/null && exit 0; sleep 2; done; exit 1' \
    || echo "   (not healthy after 2 min - InSpec will show what is wrong)"

  echo ">> InSpec smoke tests on $NODE"
  cinc-auditor exec --no-distinct-exit "$REPO_ROOT/test/smoke" \
    -t "ssh://$DEPLOY_USER@$NODE" -i "$DEPLOY_KEY" \
    --input expected_env="$GROUP" expected_version="$EXPECTED_VERSION" \
    --reporter cli "junit2:$REPO_ROOT/reports/smoke-$GROUP-$NODE.xml" \
    --no-color
done
