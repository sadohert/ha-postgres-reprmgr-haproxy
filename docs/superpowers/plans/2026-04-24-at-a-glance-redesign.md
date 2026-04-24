# DC1 "At a Glance" Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scope the "At a Glance" dashboard row to declared DC1 nodes only, with all panels repeating on `$dc1_nodes` and unreachable nodes rendering red.

**Architecture:** Four JSON edits to `monitoring/grafana/dashboards/ha_cluster.json` — one per At a Glance panel. Each edit changes the repeat variable from `instance` to `dc1_nodes`, updates the PromQL to match, and adds a `noValue: "-1"` + base-red threshold so Grafana renders a missing node red instead of grey. Panel 34 additionally converts from a single multi-series stat to a proper repeating panel. After all edits, the working copy is synced and pushed live via `scripts/push-dashboard.sh`.

**Tech Stack:** Python 3 (JSON editing), Grafana 12 (dashboard JSON schema v42), Prometheus, `scripts/push-dashboard.sh` (SCP + Grafana provisioning reload)

---

## File Map

| File | Action |
|------|--------|
| `docs/grafana/ha-cluster-dashboard.json` | **Modify** — working copy, all panel edits happen here |
| `monitoring/grafana/dashboards/ha_cluster.json` | Auto-synced by `push-dashboard.sh` — do not edit directly |

---

### Task 1: Convert Panel 34 (DC1 Node Health) to repeating

Panel 34 currently shows all three DC1 nodes as separate series in a single stat panel. This task converts it to a repeating stat panel — one panel per node — aligned above the Role/CPU/Load columns.

**Files:**
- Modify: `docs/grafana/ha-cluster-dashboard.json`

- [ ] **Step 1: Apply panel 34 changes via Python**

```bash
python3 - <<'EOF'
import json

path = "docs/grafana/ha-cluster-dashboard.json"
with open(path) as f:
    d = json.load(f)

for p in d["panels"]:
    if p["id"] == 34:
        # Make it a repeating panel
        p["repeat"] = "dc1_nodes"
        p["repeatDirection"] = "h"

        # Title uses the repeated variable
        p["title"] = "Health: ${dc1_nodes}"

        # Show value only — node name is in the title
        p["options"]["textMode"] = "value"
        p["options"]["colorMode"] = "background"
        p["options"]["graphMode"] = "none"

        # No-data → -1 → falls below green threshold → red
        p["options"]["noValue"] = "-1"

        # Fix datasource to use the template variable (was hardcoded "prometheus")
        p["datasource"] = {"type": "prometheus", "uid": "${DS_PROMETHEUS}"}

        # Exact match for the repeated instance (was =~"$dc1_nodes")
        p["targets"][0]["datasource"] = {"type": "prometheus", "uid": "${DS_PROMETHEUS}"}
        p["targets"][0]["expr"] = 'up{instance="$dc1_nodes", job="postgres"}'
        p["targets"][0]["legendFormat"] = "Health"

        # Thresholds: null(base)=red, 1=green  — already correct, leave as-is
        # Value mappings: add -1 → "no data"
        existing_mappings = p["fieldConfig"]["defaults"]["mappings"]
        # existing: 0→UNREACHABLE(red), 1→REACHABLE(green)
        # add special value mapping for -1
        existing_mappings.append({
            "type": "value",
            "options": {
                "-1": {
                    "text": "no data",
                    "color": "red",
                    "index": 2
                }
            }
        })
        print(f"Panel 34 updated: repeat=dc1_nodes, noValue=-1")
        break

with open(path, "w") as f:
    json.dump(d, f, indent=2)
EOF
```

- [ ] **Step 2: Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('docs/grafana/ha-cluster-dashboard.json')); print('JSON valid')"
```

Expected output: `JSON valid`

- [ ] **Step 3: Commit**

```bash
git add docs/grafana/ha-cluster-dashboard.json
git commit -m "feat: panel 34 — convert DC1 Node Health to repeating stat per dc1_nodes"
```

---

### Task 2: Convert Panel 30 (Role) to dc1_nodes repeat

**Files:**
- Modify: `docs/grafana/ha-cluster-dashboard.json`

- [ ] **Step 1: Apply panel 30 changes via Python**

```bash
python3 - <<'EOF'
import json

path = "docs/grafana/ha-cluster-dashboard.json"
with open(path) as f:
    d = json.load(f)

for p in d["panels"]:
    if p["id"] == 30:
        # Switch repeat variable
        p["repeat"] = "dc1_nodes"
        # repeatDirection already "h" — leave as-is

        # Title
        p["title"] = "Role: ${dc1_nodes}"

        # No-data → -1 → red
        p["options"]["noValue"] = "-1"

        # PromQL: exact match on dc1_nodes
        p["targets"][0]["expr"] = 'pg_replication_is_replica{job="postgres",instance="$dc1_nodes"}'

        # Add base-red threshold so -1 renders red
        p["fieldConfig"]["defaults"]["thresholds"]["steps"] = [
            {"color": "red", "value": None},   # base (anything below 0, incl. -1)
            {"color": "green", "value": 0}      # 0 or 1 = valid role values
        ]

        # Add -1 → "no data" value mapping alongside existing 0/1 mappings
        for override in p["fieldConfig"]["overrides"]:
            if override["matcher"]["options"] == "Role":
                for prop in override["properties"]:
                    if prop["id"] == "mappings":
                        prop["value"].append({
                            "type": "value",
                            "options": {
                                "-1": {
                                    "color": "red",
                                    "index": 2,
                                    "text": "no data"
                                }
                            }
                        })
        print("Panel 30 updated: repeat=dc1_nodes, noValue=-1, base-red threshold")
        break

with open(path, "w") as f:
    json.dump(d, f, indent=2)
EOF
```

- [ ] **Step 2: Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('docs/grafana/ha-cluster-dashboard.json')); print('JSON valid')"
```

Expected output: `JSON valid`

- [ ] **Step 3: Commit**

```bash
git add docs/grafana/ha-cluster-dashboard.json
git commit -m "feat: panel 30 — Role repeats on dc1_nodes, no-data renders red"
```

---

### Task 3: Convert Panel 31 (CPU) to dc1_nodes repeat

**Files:**
- Modify: `docs/grafana/ha-cluster-dashboard.json`

- [ ] **Step 1: Apply panel 31 changes via Python**

```bash
python3 - <<'EOF'
import json

path = "docs/grafana/ha-cluster-dashboard.json"
with open(path) as f:
    d = json.load(f)

for p in d["panels"]:
    if p["id"] == 31:
        # Switch repeat variable
        p["repeat"] = "dc1_nodes"

        # Title
        p["title"] = "CPU: ${dc1_nodes}"

        # No-data → -1 → red
        p["options"]["noValue"] = "-1"

        # PromQL: exact match on dc1_nodes
        p["targets"][0]["expr"] = (
            '100 - (avg by (instance) (rate(node_cpu_seconds_total'
            '{job="postgres",mode="idle", instance=~"$dc1_nodes"}[1m])) * 100)'
        )

        # Add base-red threshold so -1 renders red
        p["fieldConfig"]["defaults"]["thresholds"]["steps"] = [
            {"color": "red", "value": None},   # base (-1 lands here → red gauge)
            {"color": "green", "value": 0},
            {"color": "red", "value": 80}
        ]
        print("Panel 31 updated: repeat=dc1_nodes, noValue=-1, base-red threshold")
        break

with open(path, "w") as f:
    json.dump(d, f, indent=2)
EOF
```

- [ ] **Step 2: Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('docs/grafana/ha-cluster-dashboard.json')); print('JSON valid')"
```

Expected output: `JSON valid`

- [ ] **Step 3: Commit**

```bash
git add docs/grafana/ha-cluster-dashboard.json
git commit -m "feat: panel 31 — CPU repeats on dc1_nodes, no-data renders red"
```

---

### Task 4: Convert Panel 28 (Load) to dc1_nodes repeat

**Files:**
- Modify: `docs/grafana/ha-cluster-dashboard.json`

- [ ] **Step 1: Apply panel 28 changes via Python**

```bash
python3 - <<'EOF'
import json

path = "docs/grafana/ha-cluster-dashboard.json"
with open(path) as f:
    d = json.load(f)

for p in d["panels"]:
    if p["id"] == 28:
        # Switch repeat variable
        p["repeat"] = "dc1_nodes"

        # Title
        p["title"] = "Load: ${dc1_nodes}"

        # No-data → -1 → red
        p["options"]["noValue"] = "-1"

        # PromQL: exact match on dc1_nodes
        p["targets"][0]["expr"] = 'node_load1{job="postgres",instance="$dc1_nodes"}'

        # Add base-red threshold so -1 renders red
        p["fieldConfig"]["defaults"]["thresholds"]["steps"] = [
            {"color": "red", "value": None},   # base (-1 → red)
            {"color": "green", "value": 0},
            {"color": "orange", "value": 4},
            {"color": "red", "value": 8}
        ]
        print("Panel 28 updated: repeat=dc1_nodes, noValue=-1, base-red threshold")
        break

with open(path, "w") as f:
    json.dump(d, f, indent=2)
EOF
```

- [ ] **Step 2: Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('docs/grafana/ha-cluster-dashboard.json')); print('JSON valid')"
```

Expected output: `JSON valid`

- [ ] **Step 3: Commit**

```bash
git add docs/grafana/ha-cluster-dashboard.json
git commit -m "feat: panel 28 — Load repeats on dc1_nodes, no-data renders red"
```

---

### Task 5: Push dashboard and visually verify

**Files:**
- Run: `scripts/push-dashboard.sh`

- [ ] **Step 1: Push working copy to live Grafana**

Run from repo root (not a worktree — the script needs `terraform.tfstate` at repo root):

```bash
bash scripts/push-dashboard.sh
```

Expected output (last two lines):
```
Grafana reload: Dashboards config reloaded
```

If the Grafana password lookup fails, run `terraform output grafana_admin_password` from `terraform/` first to confirm Terraform state is accessible.

- [ ] **Step 2: Open Grafana and verify At a Glance section**

Open http://18.234.178.155:3000, navigate to the **Mattermost HA Cluster** dashboard.

Verify:
- [ ] "At a Glance" row shows **4 rows × 3 columns** (Health, Role, CPU, Load — one column per DC1 node)
- [ ] Panel titles read `Health: pg1`, `Health: pg2`, `Health: pg3` (not "DC1 Node Health")
- [ ] All three Health panels show green / "REACHABLE" (all nodes are up)
- [ ] Role panels show 👑 PRIMARY for pg1, 📋 REPLICA for pg2 and pg3
- [ ] **No pg4, pg5, pg6 appear anywhere in the At a Glance section**
- [ ] DC2 nodes still appear correctly in the collapsed "Cross-DC / DC2 Replication" section

- [ ] **Step 3: Sync provisioning file and commit**

The `push-dashboard.sh` script already syncs `docs/grafana/ha-cluster-dashboard.json` → `monitoring/grafana/dashboards/ha_cluster.json`. Commit the provisioning file:

```bash
git add monitoring/grafana/dashboards/ha_cluster.json
git commit -m "chore: sync provisioning file after At a Glance redesign"
```

- [ ] **Step 4: (Optional) Simulate a missing node**

To verify the red error signal without taking a node down, temporarily edit a DC1 node's scrape config or use the Grafana "Transform" feature to filter out one node. Alternatively, check by inspecting the panel JSON in the Grafana UI — confirm `noValue` is set to `"-1"` on all four panel types.
