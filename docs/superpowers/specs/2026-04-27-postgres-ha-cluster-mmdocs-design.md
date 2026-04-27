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

## Documentation structure principles

Per leadership guidance, all MM docs guides must follow these principles:

1. **Requirements upfront** — all prerequisites consolidated in one place, not scattered across setup phases
2. **Decision guidance** — help the admin make deployment decisions before they start, so they know what they need to be successful
3. **Phased approach with pass/fail verification** — each phase ends with explicit pass/fail checks the admin runs before moving on
4. **Numbered phases and steps** — phases (Phase 1, Phase 2…) and steps within phases (1.1, 1.2…) so admins can communicate to support exactly where they got stuck

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

### Section 2 — Before you begin (decision guidance)

New section — helps the admin decide if this architecture is right for them and plan what they need before touching a server. Covers:

- **Is this right for me?** — decision table: single-DC HA vs. managed DB (RDS) vs. bare-metal. When to choose each.
- **What you'll need** — hardware, network, OS, package versions, a free VIP address, SSH access. All requirements in one place — nothing repeated or scattered in later phases.
- **Node planning worksheet** — table with columns for node name, IP, role; admin fills this in before starting
- **Port reference** — complete list of ports that must be open between nodes (22, 5432, 8008, 5000, 5001) and from clients (5000, 5001)
- **Time estimate** — honest estimate for a first-time setup (~2–3 hours)

### Section 3 — Setup guide

Source: `docs/02-setup-guide.md` (all phases)

Numbered phases with numbered steps within each phase (e.g. step 2.3). Each phase ends with a **Verification checkpoint** block containing explicit pass/fail checks the admin runs before moving to the next phase.

**Phase 1 — Base configuration (all nodes)**
- 1.1 Configure `/etc/hosts`
- 1.2 Install PostgreSQL 17 and repmgr 5.5
- ✅ **Phase 1 checkpoint** — PostgreSQL starts on all nodes, repmgr binary present

**Phase 2 — Primary node setup**
- 2.1 Configure `postgresql.conf` (wal_level, hot_standby, replication slots)
- 2.2 Configure `pg_hba.conf` for replication user
- 2.3 Create replication user and repmgr database
- 2.4 Register primary with repmgr
- ✅ **Phase 2 checkpoint** — `repmgr cluster show` lists pg1 as primary; replication slot visible

**Phase 3 — Standby nodes**
- 3.1 Clone standby from primary (`repmgr standby clone`)
- 3.2 Register standbys
- 3.3 Start repmgrd on all nodes
- ✅ **Phase 3 checkpoint** — `repmgr cluster show` lists pg2 and pg3 as running standbys; `pg_stat_replication` on pg1 shows 2 connected replicas

**Phase 4 — HAProxy and VIP**
- 4.1 Install and configure HAProxy (all nodes)
- 4.2 Deploy pgchk.py health check
- 4.3 Install and configure Keepalived
- ✅ **Phase 4 checkpoint** — VIP is active on pg1; `psql -h <VIP> -p 5000` connects to primary; `psql -h <VIP> -p 5001` connects to a replica

**Phase 5 — End-to-end validation**

Source: `docs/06-failure-simulation.md`

Framed as a validation checklist — confirms HA behaviour before the cluster is handed over for production use:

- 5.1 Simulate primary failure; verify standby promotion (pass = new primary elected within 30s)
- 5.2 Verify HAProxy reroutes writes to new primary on port 5000 (pass = connection succeeds)
- 5.3 Verify VIP moves to new primary node
- 5.4 Restart old primary; verify it rejoins as standby (pass = `repmgr cluster show` shows all nodes healthy)

### Section 4 — Day-2 operations

Source: `docs/03-operations-guide.md`

- Check cluster status (`repmgr cluster show`)
- Check replication lag (via `pg_stat_replication`)
- Add a standby node
- Remove a standby node
- Manually trigger a controlled switchover
- Rejoining a failed node after recovery

### Section 5 — Troubleshooting

Source: `docs/04-troubleshooting-guide.md`

Symptom-first format: each entry states the observed symptom, likely cause, and resolution steps.

- repmgrd not starting
- Standby not replicating
- VIP not moving on failover
- HAProxy reporting all backends down
- Split-brain prevention

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
