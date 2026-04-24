# DC1 "At a Glance" Section Redesign

**Date:** 2026-04-24  
**Issue:** [#6 — DR HA Postgres Dashboard](https://github.com/sadohert/ha-postgres-reprmgr-haproxy/issues/6)  
**Dashboard:** `monitoring/grafana/dashboards/ha_cluster.json` (uid: `mattermost-ha-cluster`)

## Goal

Scope the "At a Glance" row to DC1 nodes only, using the explicitly declared `$dc1_nodes` variable instead of the auto-detected `$instance` variable. DC2 nodes must not appear here. Missing/unreachable nodes must render red immediately.

## Current State

The "At a Glance" row contains 4 panels:

| Panel ID | Title | Repeat variable | PromQL (abbreviated) |
|----------|-------|-----------------|----------------------|
| 34 | DC1 Node Health | — (single panel) | `up{instance=~"$dc1_nodes", job="postgres"}` |
| 30 | Role: ${instance} | `instance` | `pg_replication_is_replica{instance="$instance"}` |
| 31 | CPU: ${instance} | `instance` | `100 - avg(rate(node_cpu_seconds_total{instance=~"$instance"}...))` |
| 28 | Load: ${instance} | `instance` | `node_load1{instance="$instance"}` |

`$instance` resolves from `label_values(pg_up{instance=~"$db_host"}, instance)` where `$db_host = pg1,pg2,pg3,pg4,pg5,pg6`. This means DC2 nodes (pg4/5/6) appear in the repeating panels.

`$dc1_nodes` is already declared as the custom variable `pg1,pg2,pg3` (hidden from the UI).

**`$instance` must not be changed** — it is used in 12 panels across lower dashboard sections (System Resources, Performance Metrics, Replication Lag Analysis, etc.).

## Target Layout

Four horizontal repeating rows, each with one panel per DC1 node:

```
[Health: pg1 🟢]   [Health: pg2 🟢]   [Health: pg3 🔴]
[Role: pg1]         [Role: pg2]         [Role: pg3 — NO DATA → red]
[CPU: pg1]          [CPU: pg2]          [CPU: pg3 — NO DATA → red]
[Load: pg1]         [Load: pg2]         [Load: pg3 — NO DATA → red]
```

All panels repeat horizontally on the `dc1_nodes` variable.

## Panel-by-Panel Changes

### Panel 34 — DC1 Node Health (stat)

**Change:** Convert from a single multi-series stat panel to a repeating stat panel.

- `repeat`: `dc1_nodes`, direction: `h`
- PromQL: `up{instance=~"$dc1_nodes", job="postgres"}` → `up{instance="$dc1_nodes", job="postgres"}` (exact match for the repeated instance)
- Title: `Health: $dc1_nodes`
- Thresholds: `0 = red`, `1 = green`
- `fieldConfig.defaults.noValue`: `"-1"` (renders below green threshold → red)
- Value mappings: `1 → "online"`, `0 → "down"`, `-1 → "no data"`

### Panel 30 — Role (stat, repeating)

**Change:** Switch repeat variable from `instance` to `dc1_nodes`.

- `repeat`: `dc1_nodes` (was `instance`)
- PromQL: `pg_replication_is_replica{job="postgres", instance="$dc1_nodes"}` (was `instance="$instance"`)
- Title: `Role: $dc1_nodes`
- `fieldConfig.defaults.noValue`: `"-1"`
- Value mappings: `0 → "👑 PRIMARY"`, `1 → "📋 REPLICA"`, `-1 → "no data"`
- Thresholds: retain existing; add no-value color = red

### Panel 31 — CPU (gauge, repeating)

**Change:** Switch repeat variable from `instance` to `dc1_nodes`.

- `repeat`: `dc1_nodes` (was `instance`)
- PromQL: `100 - (avg by (instance) (rate(node_cpu_seconds_total{job="postgres", mode="idle", instance=~"$dc1_nodes"}[1m])) * 100)`
- Title: `CPU: $dc1_nodes`
- `fieldConfig.defaults.noValue`: `"-1"` → renders at bottom of gauge (below green threshold → red)

### Panel 28 — Load (stat, repeating)

**Change:** Switch repeat variable from `instance` to `dc1_nodes`.

- `repeat`: `dc1_nodes` (was `instance`)
- PromQL: `node_load1{job="postgres", instance="$dc1_nodes"}` (was `instance="$instance"`)
- Title: `Load: $dc1_nodes`
- `fieldConfig.defaults.noValue`: `"-1"`
- Thresholds: retain existing (green <4, orange <8, red ≥8); no-value falls at -1 → red

## Variables — No Changes Required

| Variable | Current value | Action |
|----------|--------------|--------|
| `$dc1_nodes` | `pg1,pg2,pg3` (hidden) | No change |
| `$dc2_nodes` | `pg4,pg5,pg6` (hidden) | No change |
| `$db_host` | `pg1,pg2,pg3,pg4,pg5,pg6` | No change |
| `$instance` | derived from `$db_host` via label_values | No change — used in lower sections |

## Error Signal Behaviour

| Scenario | Panel appearance |
|----------|-----------------|
| Node healthy | Green stat/gauge with metric value |
| Node `up=0` (postgres exporter running but DB down) | Red stat showing "down" |
| Node fully unreachable (no scrape) | `noValue=-1` → falls below green threshold → red, shows "no data" |

## Out of Scope

- Changing `$instance` or any lower-section panels
- DC2 node visibility (handled by the separate "Cross-DC / DC2 Replication" collapsed row)
- Adding new metrics to the At a Glance section
