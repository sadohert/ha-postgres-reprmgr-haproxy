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
  mattermost-load-test-ng/       ← Playwright install (node_modules with @playwright/test)
```

Find `<parent>` by going up one level from the ha-postgres repo root. If in doubt, ask the user.

## Step 1: Get the time range

If the user hasn't provided `FROM_TIME` and `TO_TIME`, ask:

> "What time range do you want to capture? Provide start and end in UTC:
> e.g. `2026-04-21 10:58:52` to `2026-04-21 13:00:00`"

Timestamps are treated as UTC by the capture script.

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

```bash
cd <parent>/mattermost-load-test-ng/browser
FROM_TIME="<from_time>" TO_TIME="<to_time>" \
  npx playwright test \
  --config "$SCRIPTS_DIR/playwright.config.ts" \
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

## Dashboard Reference

| Instance | Dashboard name | UID |
|----------|---------------|-----|
| ha-postgres | Mattermost HA Cluster | `mattermost-ha-cluster` |
| mm-loadtest | Load-Test Performance Monitoring | `000000011` |
| mm-loadtest | Mattermost Performance Monitoring v2 | `im7xNX17kdd` |

## Troubleshooting

**Login failure for ha-postgres**: Check the Grafana admin password with `terraform output -raw grafana_admin_password` from the terraform directory and compare against the `password` field in `grafana-capture.config.ts`.

**`npx playwright test` not found**: Make sure you're running from `mattermost-load-test-ng/browser/` where `node_modules/@playwright/test` is installed. Run `npm install` first if needed.

**Dashboard shows "No data"**: The time range may fall outside the window where metrics exist. Verify the range against Prometheus data: `curl -s "http://<monitor_ip>:9090/api/v1/query?query=up" | python3 -m json.tool | grep value`.

**Renderer not available (HA Postgres Grafana only)**: PNG screenshots via Playwright don't need the Grafana image renderer — the renderer is only needed for Grafana's built-in Share → Export feature.
