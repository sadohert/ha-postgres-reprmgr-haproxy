#!/usr/bin/env bash
# Post a timestamped annotation to the HA Cluster Grafana dashboard.
#
# Usage:
#   annotate-grafana.sh "2026-04-27 13:34:52" "pg2 stopped — SC-02 start" sc-02,failover
#   annotate-grafana.sh now "pg1 promoted to primary" sc-02,failover
#
# Arguments:
#   $1  Timestamp — "YYYY-MM-DD HH:MM:SS" (local time), or "now"
#   $2  Annotation text
#   $3  Comma-separated tags (optional, default: validation)
#
# Environment:
#   GRAFANA_URL   — defaults to http://50.19.32.175:3000
#   GRAFANA_PASS  — defaults to terraform output grafana_admin_password

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

GRAFANA_URL="${GRAFANA_URL:-http://50.19.32.175:3000}"
GRAFANA_PASS="${GRAFANA_PASS:-$(cd "$TERRAFORM_DIR" && terraform output -raw grafana_admin_password 2>/dev/null)}"
DASHBOARD_UID="mattermost-ha-cluster"

TS="${1:?Usage: $0 <timestamp|now> <text> [tags]}"
TEXT="${2:?Usage: $0 <timestamp|now> <text> [tags]}"
TAGS="${3:-validation}"

# Convert timestamp to epoch milliseconds
if [[ "$TS" == "now" ]]; then
  EPOCH_MS=$(( $(date +%s) * 1000 ))
else
  # Treat as local time (matching Grafana browser timezone)
  EPOCH_MS=$(python3 -c "
import datetime, time
dt = datetime.datetime.strptime('$TS', '%Y-%m-%d %H:%M:%S')
print(int(dt.timestamp() * 1000))
")
fi

# Build tags JSON array
TAGS_JSON=$(python3 -c "
import json
print(json.dumps('$TAGS'.split(',')))
")

PAYLOAD=$(python3 -c "
import json
print(json.dumps({
  'dashboardUID': '$DASHBOARD_UID',
  'time': $EPOCH_MS,
  'text': '$TEXT',
  'tags': $TAGS_JSON
}))
")

RESULT=$(curl -sf -X POST "$GRAFANA_URL/api/annotations" \
  -H "Content-Type: application/json" \
  -u "admin:$GRAFANA_PASS" \
  -d "$PAYLOAD")

ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id','?'))")
echo "Annotation posted (id=$ID): [$TS] $TEXT [tags: $TAGS]"
