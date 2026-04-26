#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# terraform.tfstate only exists in the main repo checkout — run from there, not from a worktree
TERRAFORM_DIR="$REPO_ROOT/terraform"
SSH_KEY="$TERRAFORM_DIR/ha-postgres-admin-key.pem"
MONITOR_HOST=$(cd "$TERRAFORM_DIR" && terraform output -raw monitor_public_ip)
GRAFANA_PASS=$(cd "$TERRAFORM_DIR" && terraform output -raw grafana_admin_password)

WORKING_COPY="$REPO_ROOT/docs/grafana/ha-cluster-dashboard.json"
PROVISIONING="$REPO_ROOT/monitoring/grafana/dashboards/ha_cluster.json"
DASHBOARD_FILE="${1:-$WORKING_COPY}"

# Step 1: Sync working copy (if caller passed a different file, copy it in)
if [[ "$DASHBOARD_FILE" != "$WORKING_COPY" ]]; then
    python3 -c "
import json
with open('$DASHBOARD_FILE') as f:
    d = json.load(f)
if 'dashboard' in d:
    d = d['dashboard']
with open('$WORKING_COPY', 'w') as f:
    json.dump(d, f, indent=2)
print('Working copy updated from $DASHBOARD_FILE')
"
fi

# Step 2: Sync provisioning file (working copy + __inputs)
python3 -c "
import json

with open('$WORKING_COPY') as f:
    live = json.load(f)

INPUTS = [{'name': 'DS_PROMETHEUS', 'label': 'Prometheus', 'description': '',
           'type': 'datasource', 'pluginId': 'prometheus', 'pluginName': 'Prometheus'}]
provisioning = {'__inputs': INPUTS}
provisioning.update(live)

with open('$PROVISIONING', 'w') as f:
    json.dump(provisioning, f, indent=2)

print(f'Provisioning file synced: {len(live[\"panels\"])} panels')
"

# Step 3: SCP provisioning file to monitor server
echo "SCPing provisioning file to $MONITOR_HOST..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "$PROVISIONING" \
    "ubuntu@${MONITOR_HOST}:/opt/monitoring/grafana/dashboards/ha_cluster.json"

# Step 4: Reload Grafana provisioning
echo "Reloading Grafana provisioning..."
RELOAD_RESULT=$(GRAFANA_PASS="$GRAFANA_PASS" MONITOR_HOST="$MONITOR_HOST" python3 -c "
import urllib.request, urllib.error, os, json

grafana_pass = os.environ['GRAFANA_PASS']
import base64
creds = base64.b64encode(f'admin:{grafana_pass}'.encode()).decode()
req = urllib.request.Request(
    f'http://{os.environ["MONITOR_HOST"]}:3000/api/admin/provisioning/dashboards/reload',
    method='POST',
    headers={'Authorization': f'Basic {creds}', 'Content-Length': '0'}
)
try:
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
        print(result.get('message', 'OK'))
except Exception as e:
    print(f'ERROR: Grafana reload failed: {e}', file=__import__('sys').stderr)
    raise
")
echo "Grafana reload: $RELOAD_RESULT"
