---
name: PostgreSQL HA Cluster — mattermost/docs contribution design
description: Design spec for contributing postgres-ha-cluster.rst to the mattermost/docs repository (issue #13)
type: project
---

# Design: PostgreSQL HA Cluster guide for mattermost/docs

**GitHub issue:** [#13](https://github.com/sadohert/ha-postgres-reprmgr-haproxy/issues/13)
**Target repo:** mattermost/docs (`source/administration-guide/scale/`)
**Status:** Ready to implement — single-DC content fully validated

---

## Decisions

| Question | Decision |
|----------|----------|
| Audience | Both self-hosted customers and PS teams (public docs) |
| Location | New sibling file in `scale/` — Option B |
| Page format | Single comprehensive RST page — Option C |
| Edition badge | None — pure infrastructure, works with any Mattermost edition |
| Multi-DC page | Separate issue #14, blocked on DC2 validation |

---

## File placement

**New file:** `source/administration-guide/scale/postgres-ha-cluster.rst`

**toctree change:** `scaling-for-enterprise.rst` — add after the existing High availability entry:
```
PostgreSQL HA cluster </administration-guide/scale/postgres-ha-cluster>
```

**Cross-link change:** `high-availability-cluster-based-deployment.rst` — update the sentence *"This document doesn't cover the configuration of databases in terms of disaster recovery"* to link to the new page.

---

## Page structure

### Opening

- Title: `PostgreSQL high availability cluster`
- No edition badge
- One-paragraph intro: infrastructure-level HA, works with any self-hosted Mattermost edition, independent of Mattermost app-layer clustering
- `.. note::` stating validated environment: Ubuntu 24.04 LTS, PostgreSQL 17, repmgr 5.5, HAProxy 2.8, Keepalived

### Section 1 — Architecture overview

Source: `docs/01-architecture-overview.md`

- ASCII architecture diagram (3-node topology: pg1 primary, pg2/pg3 standby, VIP)
- Component table: PostgreSQL 17, repmgr 5.5, HAProxy 2.8, Keepalived, pgchk.py health check script
- HAProxy port table: 5000 (write → primary), 5001 (read → any replica)
- Sizing note: link to Mattermost scaling guides; architecture supports up to ~2,000 concurrent users as a baseline

### Section 2 — Prerequisites

Source: `docs/02-setup-guide.md` §Prerequisites

- Hardware: 3 × Ubuntu 24.04 LTS, min 2 CPU / 4 GB RAM / 50 GB storage per node
- Network: ports 22, 5432, 8008, 5000, 5001 open between nodes; one free VIP address on same subnet
- Node/IP table (placeholder values: pg1/pg2/pg3 + VIP)
- SSH access with sudo on all nodes

### Section 3 — Setup guide

Source: `docs/02-setup-guide.md` (all phases)

Subsections follow the validated setup phases:

1. Configure `/etc/hosts` on all nodes
2. Install PostgreSQL 17 and repmgr 5.5 (all nodes)
3. Configure PostgreSQL on the primary (pg1)
4. Configure repmgr on the primary and register
5. Clone and register standbys (pg2, pg3)
6. Start and verify repmgrd on all nodes
7. Install and configure HAProxy (all nodes)
8. Install and configure Keepalived for VIP (all nodes)
9. Deploy pgchk.py health check endpoint
10. Verify cluster health end-to-end

Each step uses `.. code-block:: bash` for commands. `.. warning::` directives flag destructive or order-sensitive steps.

### Section 4 — Day-2 operations

Source: `docs/03-operations-guide.md`

- Check cluster status (`repmgr cluster show`)
- Check replication lag (via `pg_stat_replication`)
- Add a standby node
- Remove a standby node
- Manually trigger a controlled switchover
- Rejoining a failed node after recovery
- Rotating replication slots

### Section 5 — Troubleshooting

Source: `docs/04-troubleshooting-guide.md`

- repmgrd not starting
- Standby not replicating
- VIP not moving on failover
- HAProxy reporting all backends down
- Split-brain prevention

### Section 6 — Failure simulation

Source: `docs/06-failure-simulation.md`

Framed as a *validation checklist* rather than a test procedure — confirms the cluster behaves as designed after setup. Covers:

- Simulate primary failure → verify automatic promotion of a standby
- Verify HAProxy reroutes writes to new primary (port 5000)
- Verify old primary rejoins as standby
- Verify VIP moves to new primary node

---

## RST conventions

- Follow existing mattermost-docs RST style (title underline `===`, section `---`, subsection `~~~`)
- `.. include:: ../../_static/badges/` — not used (no edition gate)
- `.. note::` for informational callouts (e.g. tested versions)
- `.. warning::` for destructive or order-sensitive steps
- `.. code-block:: bash` for all shell commands
- Internal cross-refs using `:doc:` and `:ref:` directives

---

## Out of scope for this page

- Multi-DC / disaster recovery (issue #14, blocked on DC2 validation)
- Monitoring setup (Prometheus/Grafana) — link to existing `deploy-prometheus-grafana-for-performance-monitoring.rst`
- Mattermost application-layer HA clustering — link to existing `high-availability-cluster-based-deployment.rst`
- Terraform/automation — the page documents manual setup steps only

---

## Branch strategy

- Base branch: `origin/main` of `mattermost/mattermost-docs` (local clone at `/Users/stu/development/mattermost-docs`)
- Working branch: `postgres-ha-cluster-guide` (created off tip of origin/main)
- PR target: `mattermost/mattermost-docs` main branch
