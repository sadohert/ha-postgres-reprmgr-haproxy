# ha-postgres-reprmgr-haproxy

Terraform + bash for a HA PostgreSQL cluster using repmgr for replication management and HAProxy for connection routing. Designed to simulate bare-metal HA on AWS (same VPC, no managed services).

## Project Conventions

### Worktrees
- Use `.worktrees/` for git worktrees (project-local, already gitignored)

### Terraform
- All new resource blocks that are not part of the base cluster must be gated with `count = var.<feature>_enabled ? N : 0` so they default to off and never affect existing infrastructure.
- **Never modify `user_data.sh.tpl`** (DC1 nodes) without confirming it won't trigger instance recreation. DC1 compute resources have `user_data_replace_on_change = true`, so any template change will destroy and recreate pg1/2/3.
- Terraform state lives at repo root (`terraform.tfstate`) — not in S3. Run all terraform commands from `terraform/`.
- AWS profile: `AWSAdministratorAccess-729462591288`

### Bash templates (`terraform/templates/*.sh.tpl`)
- Use `<<EOF` (unquoted) when the heredoc body needs Terraform variable interpolation (`${var}`).
- Use `<<'EOF'` only when the body must be treated as literal (no Terraform interpolation).
- Never use `<<-EOF` unless the closing delimiter is tab-indented — space indentation causes the heredoc to never close.

### Monitoring (Grafana + Prometheus)
- Docker Compose stack lives at `/opt/monitoring/` on the monitor EC2 instance.
- Grafana runs on port 3000; Prometheus on 9090; Loki on 3100.
- Image renderer container (`grafana/grafana-image-renderer`) listens on port **8081** — `GF_RENDERING_SERVER_URL` must point to port 8081, not 3000.
- Grafana v13 requires `AUTH_TOKEN` on the renderer container and `GF_RENDERING_RENDERER_TOKEN` on Grafana to match.
- PDF export is Grafana Enterprise only. Use the image renderer for PNG panel exports or Playwright for full-dashboard screenshots.

### Grafana Screenshot Capture
Dashboard screenshots are captured via Playwright in the `.worktrees/grafana-capture/` worktree, which has its own `node_modules` — do not use any other playwright install.

**Run a capture:**
```bash
cd .worktrees/grafana-capture
FROM_TIME="2026-04-21 10:58:52" TO_TIME="2026-04-21 11:32:14" \
  npx playwright test --config=scripts/playwright.config.ts
# Single dashboard: add --grep "ha-cluster"
```

Key gotchas:
- **Timestamps are LOCAL time** (EDT/EST), matching what you type into Grafana's time picker. The spec does NOT append a UTC `Z` suffix.
- **`var-server` is auto-discovered** at runtime via the Grafana/Prometheus targets API. Config entries use `server: '$all'` as sentinel — no hardcoded host lists.
- **Do not use `networkidle`** — a broken Grafana plugin makes endless failing requests so it never fires. The spec uses scroll-to-trigger (500 ms/step) + 15 s fixed wait.
- **Playwright test timeout is 180 s** — do not lower it.
- **Dashboard config:** `scripts/grafana-capture.config.ts` — add Grafana instances/dashboards here. Screenshots land in `screenshots/`.

## Architecture

```
DC1 (always on)                  DC2 (dc2_enabled = true)
node1 primary ──────────────────► node4 upstream standby
  ├── node2 standby                   ├── node5 standby
  └── node3 standby                   └── node6 standby

HAProxy (DC1 NLB):
  port 5000 → primary (write)
  port 5001 → any replica (read)

Monitoring server:
  Prometheus + Grafana + Loki (Docker Compose)
  Scrapes all 6 postgres nodes + Mattermost app servers
```

## Key Infrastructure Details

| Resource | Value |
|----------|-------|
| Monitor public IP | 18.234.178.155 |
| Monitor SSH | `ssh -i terraform/ha-postgres-admin-key.pem ubuntu@18.234.178.155` |
| Grafana URL | http://18.234.178.155:3000 |
| Grafana admin password | See `terraform output grafana_admin_password` |
| DC2 upstream (pg4) | 54.198.206.31 |
| DC2 standbys (pg5/6) | 44.197.193.166, 52.207.184.76 |

## DC2 repmgr settings (differs from DC1)

| Setting | DC1 | DC2 |
|---------|-----|-----|
| `failover` | `automatic` | `manual` |
| `priority` | 100 (default) | `0` |
| `location` | *(unset)* | `dc2` |
| `upstream_node_id` | *(unset)* | explicit |

## Confluence Validation Documentation

Validation results are documented under the **Midmarket HA DR Postgres Cluster - Validation Guides** parent page in the CO (Customer Operations) space.

| Item | Value |
|------|-------|
| Atlassian base URL | `https://mattermost.atlassian.net` |
| Space key | `CO` |
| Space ID | `1509490749` |
| Cloud ID | `7692e0ee-8b8d-44e0-8e07-372f61f93e98` |
| Parent page ID | `4489084941` |
| Auth env vars | `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`, `ATLASSIAN_BASE_URL` (set in `~/.claude/settings.json`) |

**Creating a page with screenshots (use REST API, not MCP):**
MCP's `createConfluencePage` tends to create drafts. Draft pages reject attachment uploads via REST API. Always create directly via REST API as `"status": "current"`:

```bash
# 1. Create page
curl -X POST -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content" \
  -d '{"type":"page","status":"current","title":"...","ancestors":[{"id":"4489084941"}],"space":{"key":"CO"},"body":{"storage":{"representation":"storage","value":"<p>placeholder</p>"}}}'

# 2. Upload each screenshot as attachment
curl -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" \
  -H "X-Atlassian-Token: no-check" \
  -F "file=@screenshot.png;type=image/png" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content/{pageId}/child/attachment"

# 3. Update page body with storage format links (NOT markdown/ADF for attachments)
# Attachment link format:
# <ac:link><ri:attachment ri:filename="screenshot.png"/><ac:plain-text-link-body><![CDATA[View screenshot]]></ac:plain-text-link-body></ac:link>
```

MCP tools (`getConfluencePage`, `updateConfluencePage`, `searchConfluenceUsingCql`) are fine for reading and text-only updates.

## Current Branch State (`feature/dc2-warm-standby-nodes`)

### What's already implemented (do not re-implement)

**Cascading replication topology fix** (`terraform/templates/user_data_dc2.sh.tpl`, section 4b)
- `repmgr standby clone` copies the source's `primary_conninfo` verbatim — it does not rewrite it to point to the immediate upstream. pg5/pg6 were streaming from pg1 instead of pg4.
- Fix: after `repmgr standby clone`, non-pg4 nodes create a replication slot on pg4, rewrite `primary_conninfo` via `ALTER SYSTEM`, restart postgres, then drop the stale slot that repmgr created on pg1.
- `compute.tf` now passes `primary_node_ip` to the DC2 template so the slot-drop can target pg1.

**`pg_wal_position` custom metric** (both `user_data.sh.tpl` and `user_data_dc2.sh.tpl`)
- Added to `metrics_queries.yaml` on every node. Reports `lsn_bytes` (WAL position from origin) labelled by `node_role` (primary/replica).
- Metric is **already live on the running cluster** — `pg_wal_position_lsn_bytes` is in Prometheus now.
- Purpose: `pg_stat_replication` goes blank when a standby fully disconnects; this metric stays populated on the replica side and enables lag computation even during a full network partition.

**Grafana HA Cluster dashboard panels** (deployed live to monitor server, dashboard uid `mattermost-ha-cluster`)
- **Panel 32 — "Replication Lag by LSN (bytes) — works when disconnected"**
  - PromQL: `clamp_min(scalar(max(pg_wal_position_lsn_bytes{node_role="primary"})) - avg by(instance) (pg_wal_position_lsn_bytes{node_role="replica"}), 0)`
  - `scalar()` is required because a straight binary op between a scalar result and a vector fails on label mismatch.
  - `avg by(instance)` collapses duplicates from DC2 nodes being scraped twice (EC2 discovery + static config both hit port 9187).
- **Panel 33 — "Node Presence"**
  - PromQL: `avg by(instance) (pg_wal_position_lsn_bytes) > bool 0`
  - Stat panel; green = exporter reachable. Includes pg1 (primary) as well as all replicas.

### Open GitHub issues (project board: https://github.com/users/sadohert/projects/5/views/1)

| # | Title | Status |
|---|-------|--------|
| [#3](https://github.com/sadohert/ha-postgres-reprmgr-haproxy/issues/3) | Grafana: replication lag metric disappears when standby disconnects | Fix implemented, **pending SC-01 validation** |
| [#4](https://github.com/sadohert/ha-postgres-reprmgr-haproxy/issues/4) | Publish findings to Mattermost community forum when validation is complete | Deferred |
| [#5](https://github.com/sadohert/ha-postgres-reprmgr-haproxy/issues/5) | Grafana and Prometheus HA — Out of scope | Deferred |

### Known technical debt

- DC2 nodes (pg4/5/6) are scraped twice by Prometheus: once via EC2 service discovery (`job="postgres"`) and once via static config (`job="postgres-dc2"`). The `avg by(instance)` in panel 32 mitigates duplication. Prometheus `prometheus.yml` should be cleaned up to remove the static DC2 entries once EC2 discovery is confirmed stable.
