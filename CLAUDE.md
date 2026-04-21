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

### Scripts
- Playwright scripts live in `scripts/` and are run using the `@playwright/test` install from `mattermost-load-test-ng/browser/`.
- Run command: `cd /Users/stu/development/mattermost-load-test-ng/browser && npx playwright test --config ../../ha-postgres-reprmgr-haproxy/scripts/playwright.config.ts`

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
