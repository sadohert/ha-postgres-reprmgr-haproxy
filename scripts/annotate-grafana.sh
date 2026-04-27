#!/usr/bin/env bash
# Post a timestamped annotation to the HA Cluster Grafana dashboard.
#
# Usage:
#   annotate-grafana.sh "2026-04-27 09:34:52" "pg2 stopped" sc-02,failover [#color]
#   annotate-grafana.sh now "pg1 promoted" sc-02,failover [#color]
#
# Color conventions (use consistently across scenarios):
#   #e02f44  red    — failure / node stopped
#   #e0752d  orange — degraded / warning state
#   #FADE2A  yellow — transition / election in progress
#   #56a64b  green  — recovery / node promoted or reconnected
#   #5794f2  blue   — manual DR step (operator action required)
#
# Arguments:
#   $1  Timestamp — "YYYY-MM-DD HH:MM:SS" (local time), or "now"
#   $2  Annotation text
#   $3  Comma-separated tags (optional, default: validation)
#   $4  Hex color (optional, default: #5794f2 blue)
#
# To update an existing annotation by ID:
#   ANNOTATION_ID=3 annotate-grafana.sh "2026-04-27 09:36:33" "updated text" tags #color
#
# Environment:
#   GRAFANA_URL     — defaults to http://50.19.32.175:3000
#   GRAFANA_PASS    — defaults to terraform output grafana_admin_password
#   ANNOTATION_ID   — if set, PATCHes that annotation instead of creating new

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

GRAFANA_URL="${GRAFANA_URL:-http://50.19.32.175:3000}"
GRAFANA_PASS="${GRAFANA_PASS:-$(cd "$TERRAFORM_DIR" && terraform output -raw grafana_admin_password 2>/dev/null)}"
DASHBOARD_UID="mattermost-ha-cluster"

TS="${1:?Usage: $0 <timestamp|now> <text> [tags] [#color]}"
TEXT="${2:?Usage: $0 <timestamp|now> <text> [tags] [#color]}"
TAGS="${3:-validation}"
COLOR="${4:-#5794f2}"

# Convert timestamp to epoch milliseconds
if [[ "$TS" == "now" ]]; then
  EPOCH_MS=$(( $(date +%s) * 1000 ))
else
  EPOCH_MS=$(python3 -c "
import datetime
dt = datetime.datetime.strptime('$TS', '%Y-%m-%d %H:%M:%S')
print(int(dt.timestamp() * 1000))
")
fi

TAGS_JSON=$(python3 -c "import json; print(json.dumps('$TAGS'.split(',')))")

PAYLOAD=$(python3 -c "
import json
print(json.dumps({
  'dashboardUID': '$DASHBOARD_UID',
  'time': $EPOCH_MS,
  'text': '$TEXT',
  'tags': $TAGS_JSON,
  'color': '$COLOR'
}))
")

if [[ -n "${ANNOTATION_ID:-}" ]]; then
  RESULT=$(curl -sf -X PATCH "$GRAFANA_URL/api/annotations/$ANNOTATION_ID" \
    -H "Content-Type: application/json" \
    -u "admin:$GRAFANA_PASS" \
    -d "$PAYLOAD")
  echo "Annotation updated (id=$ANNOTATION_ID): [$TS] $TEXT [tags: $TAGS] [color: $COLOR]"
else
  RESULT=$(curl -sf -X POST "$GRAFANA_URL/api/annotations" \
    -H "Content-Type: application/json" \
    -u "admin:$GRAFANA_PASS" \
    -d "$PAYLOAD")
  ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id','?'))")
  echo "Annotation posted (id=$ID): [$TS] $TEXT [tags: $TAGS] [color: $COLOR]"
fi
