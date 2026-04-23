#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# terraform.tfstate is gitignored — it only exists in the main repo, not this worktree
TERRAFORM_DIR="/Users/stu/development/ha-postgres-reprmgr-haproxy/terraform"
GRAFANA_PASS=$(cd "$TERRAFORM_DIR" && terraform output -raw grafana_admin_password)
WORKING_COPY="$REPO_ROOT/docs/grafana/ha-cluster-dashboard.json"
PROVISIONING="$REPO_ROOT/monitoring/grafana/dashboards/ha_cluster.json"
DASHBOARD_FILE="${1:-$WORKING_COPY}"

# Push to Grafana
PAYLOAD=$(python3 -c "
import json, sys
with open('$DASHBOARD_FILE') as f:
    db = json.load(f)
if 'dashboard' in db:
    db = db['dashboard']
db.pop('version', None)
db.pop('id', None)
print(json.dumps({'dashboard': db, 'overwrite': True, 'folderId': 0}))
")

RESULT=$(curl -s -X POST \
  -u "admin:${GRAFANA_PASS}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "http://18.234.178.155:3000/api/dashboards/db")

echo "$RESULT" | python3 -m json.tool
echo "$RESULT" | python3 -c "import json,sys; r=json.load(sys.stdin); exit(0 if r.get('status')=='success' else 1)"

# Sync working copy and provisioning file from what was just pushed
python3 -c "
import json, urllib.request, base64

creds = base64.b64encode(b'admin:${GRAFANA_PASS}').decode()
req = urllib.request.Request(
    'http://18.234.178.155:3000/api/dashboards/uid/mattermost-ha-cluster',
    headers={'Authorization': f'Basic {creds}'}
)
with urllib.request.urlopen(req) as resp:
    live = json.loads(resp.read())['dashboard']

# Save working copy (raw dashboard JSON)
with open('$WORKING_COPY', 'w') as f:
    json.dump(live, f, indent=2)

# Save provisioning file — must include __inputs for Grafana import compatibility
INPUTS = [{'name': 'DS_PROMETHEUS', 'label': 'Prometheus', 'description': '',
           'type': 'datasource', 'pluginId': 'prometheus', 'pluginName': 'Prometheus'}]
provisioning = {'__inputs': INPUTS}
provisioning.update(live)
with open('$PROVISIONING', 'w') as f:
    json.dump(provisioning, f, indent=2)

print(f'Synced: {len(live[\"panels\"])} panels')
print(f'  Working copy: $WORKING_COPY')
print(f'  Provisioning: $PROVISIONING')
"
