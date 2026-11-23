#!/usr/bin/env bash
# Release an application version to a policy group:
#   write releases/myapp_<group> data bag item -> converge -> verify.
# Used by the myapp Jenkins pipeline, and by you for a manual ROLLBACK:
#   DEPLOY_KEY=~/key ci/release_app.sh prod 1.0.12 <sha256>
. "$(dirname "$0")/lib.sh"
GROUP="${1:?usage: release_app.sh <group> <version> <sha256> [artifact_base_url]}"
VERSION="${2:?version required}"
SHA256="${3:?sha256 required}"
BASE_URL="${4:-http://jenkins.lab.internal:8081/myapp}"
cd "$REPO_ROOT"

knife ssl fetch -c "$KNIFE_CFG" >/dev/null 2>&1 || true

TMPDIR_ITEM="$(mktemp -d)"
ITEM="$TMPDIR_ITEM/myapp_${GROUP}.json"
cat > "$ITEM" <<JSON
{
  "id": "myapp_${GROUP}",
  "version": "${VERSION}",
  "sha256": "${SHA256}",
  "url": "${BASE_URL}/myapp-${VERSION}.jar",
  "released_by": "${BUILD_TAG:-$(whoami)}",
  "released_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
echo "=== Release myapp ${VERSION} to '${GROUP}' ==="
cat "$ITEM"
knife data bag create releases -c "$KNIFE_CFG" >/dev/null 2>&1 || true
knife data bag from file releases "$ITEM" -c "$KNIFE_CFG"
rm -rf "$TMPDIR_ITEM"

ci/converge.sh "$GROUP"
ci/smoke.sh "$GROUP" "$VERSION"
