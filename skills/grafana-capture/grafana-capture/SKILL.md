---
name: grafana-capture
description: "Capture full-page PNG screenshots of Grafana dashboards from the HA Postgres and Mattermost Load Test environments using Playwright. Use this skill whenever the user wants to screenshot, capture, export, or save Grafana dashboards — especially before tearing down a demo environment. Triggers on: 'capture dashboards', 'screenshot Grafana', 'save the dashboards', 'export dashboard', 'grab Grafana screenshots', or any mention of preserving/documenting the current state of Grafana before a teardown."
---

# Grafana Dashboard Capture

Captures screenshots from both Grafana instances (HA Postgres + MM Load Test) using Playwright, with automatic IP discovery from live infrastructure.

## Repo Layout Assumption

Both repos are siblings under the same parent directory:
```
<parent>/
  ha-postgres-reprmgr-haproxy/   ← Terraform, scripts, this skill
  mattermost-load-test-ng/       ← (load test tooling — not used for Playwright)
```

Find `<parent>` by going up one level from the ha-postgres repo root. If in doubt, ask the user.

## Step 1: Get the time range

If the user hasn't provided `FROM_TIME` and `TO_TIME`, ask:

> "What time range do you want to capture? Provide start and end as local time (EDT/EST — whatever you'd type into Grafana's time picker):
> e.g. `2026-04-21 10:58:52` to `2026-04-21 13:00:00`"

Timestamps are **local time (EDT/EST)**, matching what the user would type into Grafana's time picker. Do NOT append a UTC `Z` suffix — the capture script passes them verbatim.

## Step 2: Locate the scripts directory

The capture scripts may be at the repo root (merged) or in a worktree (feature branch). Detect which:

```bash
# Check merged location first
if [ -f "<parent>/ha-postgres-reprmgr-haproxy/scripts/playwright.config.ts" ]; then
  SCRIPTS_DIR="<parent>/ha-postgres-reprmgr-haproxy/scripts"
  SCREENSHOTS_DIR="<parent>/ha-postgres-reprmgr-haproxy/screenshots"
else
  # Fall back to worktree location
  SCRIPTS_DIR=$(find "<parent>/ha-postgres-reprmgr-haproxy/.worktrees" \
    -name "playwright.config.ts" -maxdepth 3 2>/dev/null | head -1 | xargs dirname)
  SCREENSHOTS_DIR="$(dirname $SCRIPTS_DIR)/screenshots"
fi
```

If neither exists, tell the user the scripts haven't been created yet and point them to `docs/superpowers/plans/2026-04-21-grafana-dashboard-capture.md`.

Use `$SCRIPTS_DIR` and `$SCREENSHOTS_DIR` for all subsequent steps.

## Step 3: Discover current Grafana IPs (run in parallel with Step 2)

Run both lookups in parallel.

**HA Postgres monitor IP** (from Terraform outputs):
```bash
cd <parent>/ha-postgres-reprmgr-haproxy/terraform
terraform output -raw monitor_public_ip 2>/dev/null
```

**MM Load Test Grafana URL** (from ltctl):
```bash
cd <parent>/mattermost-load-test-ng
go run ./cmd/ltctl deployment info 2>/dev/null | grep "Grafana URL" | awk '{print $3}'
```

If either command fails (environment not deployed), tell the user which one failed and ask whether to proceed with the hardcoded config values or skip that Grafana instance.

## Step 4: Sync IPs into the config if they've changed

Open `$SCRIPTS_DIR/grafana-capture.config.ts`.

Compare the discovered IPs against the `url` fields in `GRAFANAS`:
- `ha-postgres` entry → should be `http://<monitor_public_ip>:3000`
- `mm-loadtest` entry → should match the ltctl Grafana URL

If either differs, update the file in-place. This keeps the config current so the next run doesn't need terraform to be available.

## Step 5: Run the capture

The worktree has its own `node_modules` — always run from the worktree root, not from any other location.

```bash
WORKTREE_DIR="$(dirname "$SCRIPTS_DIR")"
cd "$WORKTREE_DIR"
FROM_TIME="<from_time>" TO_TIME="<to_time>" \
  npx playwright test --config=scripts/playwright.config.ts \
  2>&1
```

Expected output: 3 tests passing, one per dashboard (`ha-cluster`, `loadtest-performance`, `mm-performance-v2`).

If a test fails, show the error and offer to retry or skip that dashboard.

## Step 6: Show results

List the PNG files created:
```bash
ls -lh "$SCREENSHOTS_DIR"/*.png 2>/dev/null
```

Then open them:
```bash
open "$SCREENSHOTS_DIR"/*.png
```

Report the full paths so the user can find them.

## Step 7: Document to Confluence (when user wants a baseline or validation page)

If the user asks to create a Confluence page, collect two things first if not already provided:
- **Test conditions description** — ask the user for a freeform sentence or two describing what's being tested (e.g. "SC-01 validation, 500 concurrent users, 10 min soak after reprovision")
- **Screenshots** from Step 6 (already in `$SCREENSHOTS_DIR`)

Use the REST API directly — not MCP's `createConfluencePage`, which creates drafts that reject attachment uploads.

### 7a: Read and sanitize the load test config files

The three config files live under `<parent>/mattermost-load-test-ng/config/`:
- `deployer.json`
- `config.json`
- `coordinator.json`

Read each file and strip any local filesystem paths that would reveal the user's machine or key file location. Look for JSON fields whose values contain an absolute path (starts with `/` or `~`) and redact the value:

```python
import json, re

def sanitize(obj):
    if isinstance(obj, dict):
        return {k: "<redacted>" if isinstance(v, str) and re.match(r'^[/~]', v) else sanitize(v)
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [sanitize(i) for i in obj]
    return obj

with open("config/deployer.json") as f:
    print(json.dumps(sanitize(json.load(f)), indent=2))
```

Run this for all three files. Use the sanitized output as the config content in the page.

### 7b: Create the page

```bash
curl -s -X POST -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content" \
  -d '{
    "type": "page",
    "status": "current",
    "title": "<title>",
    "ancestors": [{"id": "4489084941"}],
    "space": {"key": "CO"},
    "body": {"storage": {"representation": "storage", "value": "<p>placeholder</p>"}}
  }' | python3 -m json.tool | grep '"id"' | head -1
```

Note the returned page ID.

### 7c: Upload screenshots as attachments (run in parallel)

```bash
curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" \
  -H "X-Atlassian-Token: no-check" \
  -F "file=@<path-to-screenshot.png>;type=image/png" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content/<pageId>/child/attachment"
```

### 7d: Update the page body

Build the body using this structure — Test Conditions first, then Configuration (inline code blocks, not attachments — easier to read), then Screenshots (collapsed expand macros):

```xml
<h2>Test Conditions</h2>
<p><USER'S FREEFORM DESCRIPTION></p>

<h2>Configuration</h2>

<h3>deployer.json</h3>
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">json</ac:parameter>
  <ac:rich-text-body><SANITIZED deployer.json CONTENT></ac:rich-text-body>
</ac:structured-macro>

<h3>config.json</h3>
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">json</ac:parameter>
  <ac:rich-text-body><SANITIZED config.json CONTENT></ac:rich-text-body>
</ac:structured-macro>

<h3>coordinator.json</h3>
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">json</ac:parameter>
  <ac:rich-text-body><SANITIZED coordinator.json CONTENT></ac:rich-text-body>
</ac:structured-macro>

<h2>Screenshots</h2>
<ac:structured-macro ac:name="expand">
  <ac:parameter ac:name="title">HA Cluster</ac:parameter>
  <ac:rich-text-body>
    <p><ac:image><ri:attachment ri:filename="<ha-cluster-filename>.png"/></ac:image></p>
  </ac:rich-text-body>
</ac:structured-macro>
<ac:structured-macro ac:name="expand">
  <ac:parameter ac:name="title">Load Test Performance</ac:parameter>
  <ac:rich-text-body>
    <p><ac:image><ri:attachment ri:filename="<loadtest-filename>.png"/></ac:image></p>
  </ac:rich-text-body>
</ac:structured-macro>
<ac:structured-macro ac:name="expand">
  <ac:parameter ac:name="title">Mattermost Performance v2</ac:parameter>
  <ac:rich-text-body>
    <p><ac:image><ri:attachment ri:filename="<mm-perf-filename>.png"/></ac:image></p>
  </ac:rich-text-body>
</ac:structured-macro>
```

Pass this as version 2 in a PUT to `$ATLASSIAN_BASE_URL/wiki/rest/api/content/<pageId>`.

Report the final page URL: `https://mattermost.atlassian.net/wiki/spaces/CO/pages/<pageId>`

## Dashboard Reference

| Instance | Dashboard name | UID |
|----------|---------------|-----|
| ha-postgres | Mattermost HA Cluster | `mattermost-ha-cluster` |
| mm-loadtest | Load-Test Performance Monitoring | `000000011` |
| mm-loadtest | Mattermost Performance Monitoring v2 | `im7xNX17kdd` |

## Troubleshooting

**Login failure for ha-postgres**: Check the Grafana admin password with `terraform output -raw grafana_admin_password` from the terraform directory and compare against the `password` field in `grafana-capture.config.ts`.

**`npx playwright test` not found or wrong version error**: Make sure you're running from the worktree root (`$(dirname $SCRIPTS_DIR)`), not from any other location. The worktree has its own `node_modules` — mixing it with another Playwright install causes version conflicts. Run `npm install` inside the worktree root if node_modules is missing.

**Dashboard shows "No data"**: The time range may fall outside the window where metrics exist. Verify the range against Prometheus data: `curl -s "http://<monitor_ip>:9090/api/v1/query?query=up" | python3 -m json.tool | grep value`.

**Renderer not available (HA Postgres Grafana only)**: PNG screenshots via Playwright don't need the Grafana image renderer — the renderer is only needed for Grafana's built-in Share → Export feature.
