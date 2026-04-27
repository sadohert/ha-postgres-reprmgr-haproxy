# PostgreSQL HA Cluster — mattermost/docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Contribute `postgres-ha-cluster.rst` to `mattermost/mattermost-docs` as a new page in `source/administration-guide/scale/`, plus two small edits to existing files.

**Architecture:** Single new RST page written from validated source docs in this repo (`docs/01–06-*.md`). Two existing files updated: `scaling-for-enterprise.rst` (toctree entry) and `high-availability-cluster-based-deployment.rst` (cross-link). All work on a branch off `origin/main` of the mattermost-docs repo.

**Tech Stack:** reStructuredText (Sphinx), mattermost-docs repo at `/Users/stu/development/mattermost-docs`

**Source docs (read-only reference):**
- `docs/01-architecture-overview.md` → Section 1 (Architecture)
- `docs/02-setup-guide.md` → Section 3 (Setup phases)
- `docs/03-operations-guide.md` → Section 4 (Day-2 ops)
- `docs/04-troubleshooting-guide.md` → Section 5 (Troubleshooting)
- `docs/06-failure-simulation.md` → Section 3 Phase 5 (Validation)

---

## Files

| Action | Path |
|--------|------|
| Create | `source/administration-guide/scale/postgres-ha-cluster.rst` |
| Modify | `source/administration-guide/scale/scaling-for-enterprise.rst` |
| Modify | `source/administration-guide/scale/high-availability-cluster-based-deployment.rst` |

---

## Task 1: Create branch in mattermost-docs

**Files:** none (git operations only)

- [ ] **Step 1.1: Fetch latest origin/main**

```bash
cd /Users/stu/development/mattermost-docs
git fetch origin
git checkout main
git merge --ff-only origin/main
```

Expected: branch `main` is up to date with `origin/main`.

- [ ] **Step 1.2: Create working branch**

```bash
git checkout -b postgres-ha-cluster-guide
```

Expected: `Switched to a new branch 'postgres-ha-cluster-guide'`

---

## Task 2: Create RST skeleton and verify build

**Files:**
- Create: `source/administration-guide/scale/postgres-ha-cluster.rst`

- [ ] **Step 2.1: Write skeleton file with all section stubs**

Create `source/administration-guide/scale/postgres-ha-cluster.rst`:

```rst
PostgreSQL high availability cluster
=====================================

:nosearch:

This guide describes how to deploy a high availability PostgreSQL cluster for
Mattermost using `repmgr <https://repmgr.org/>`__ for replication management
and automatic failover, `HAProxy <https://www.haproxy.org/>`__ for connection
routing, and `Keepalived <https://keepalived.org/>`__ for Virtual IP (VIP)
management.

This is infrastructure-level HA that operates independently of your Mattermost
edition. It is compatible with any self-hosted Mattermost deployment.

.. note::

   This guide has been validated on: **Ubuntu 24.04 LTS**, **PostgreSQL 17**,
   **repmgr 5.5**, **HAProxy 2.8**, **Keepalived**.

Architecture overview
---------------------

[stub]

Before you begin
----------------

[stub]

Setup guide
-----------

[stub]

Day-2 operations
----------------

[stub]

Troubleshooting
---------------

[stub]
```

- [ ] **Step 2.2: Verify RST is valid by running a partial Sphinx build**

```bash
cd /Users/stu/development/mattermost-docs
pipenv run sphinx-build -b html source build/html source/administration-guide/scale/postgres-ha-cluster.rst 2>&1 | tail -20
```

Expected: no `ERROR` lines. Warnings about missing toctree entry are acceptable at this stage.

- [ ] **Step 2.3: Commit skeleton**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: add postgres-ha-cluster.rst skeleton"
```

---

## Task 3: Write Section 1 — Architecture overview

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

Source: `docs/01-architecture-overview.md`

- [ ] **Step 3.1: Replace `[stub]` in Architecture overview section with full content**

Replace the `Architecture overview` section stub with:

```rst
Architecture overview
---------------------

A PostgreSQL HA cluster for Mattermost consists of three nodes running in
parallel. Each node runs the full stack: PostgreSQL, repmgr daemon (repmgrd),
HAProxy, Keepalived, and a health-check service. A Virtual IP (VIP) floats
across nodes and always points to the current primary.

.. code-block:: text

                         VIP: <CLUSTER_VIP>
                                │
                ┌───────────────┼───────────────┐
                │               │               │
         ┌──────┴──────┐ ┌──────┴──────┐ ┌──────┴──────┐
         │     pg1     │ │     pg2     │ │     pg3     │
         │             │ │             │ │             │
         │  HAProxy    │ │  HAProxy    │ │  HAProxy    │
         │  Keepalived │ │  Keepalived │ │  Keepalived │
         │  pgchk.py   │ │  pgchk.py   │ │  pgchk.py   │
         │  repmgrd    │ │  repmgrd    │ │  repmgrd    │
         ├─────────────┤ ├─────────────┤ ├─────────────┤
         │ PostgreSQL  │ │ PostgreSQL  │ │ PostgreSQL  │
         │   PRIMARY   │ │   STANDBY   │ │   STANDBY   │
         └─────────────┘ └─────────────┘ └─────────────┘

**Components:**

.. list-table::
   :widths: 20 10 70
   :header-rows: 1

   * - Component
     - Version
     - Role
   * - PostgreSQL
     - 17
     - Primary database engine. Streaming replication with replication slots.
   * - repmgr / repmgrd
     - 5.5
     - Replication manager. Monitors cluster health and automatically promotes
       a standby when the primary fails.
   * - HAProxy
     - 2.8
     - TCP load balancer. Routes write traffic to the primary and read traffic
       to standbys via two ports.
   * - Keepalived
     - —
     - Manages the VIP using VRRP. Moves the VIP to the new primary after
       failover.
   * - pgchk.py
     - —
     - HTTP health-check endpoint (port 8008). HAProxy queries this to
       determine which node is the current primary.

**HAProxy ports:**

.. list-table::
   :widths: 15 85
   :header-rows: 1

   * - Port
     - Purpose
   * - 5000
     - Write traffic — routes to the current primary only
   * - 5001
     - Read traffic — load-balanced across all standbys

**Sizing:** This architecture is appropriate for Mattermost deployments up to
approximately 2,000 concurrent users. For larger deployments, see
:doc:`Scaling for Enterprise </administration-guide/scale/scaling-for-enterprise>`.
```

- [ ] **Step 3.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — architecture overview section"
```

---

## Task 4: Write Section 2 — Before you begin

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

- [ ] **Step 4.1: Replace `[stub]` in Before you begin section**

Replace the `Before you begin` stub with:

```rst
Before you begin
----------------

Is this the right architecture for you?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. list-table::
   :widths: 30 35 35
   :header-rows: 1

   * - Scenario
     - Recommendation
     - Why
   * - Cloud-hosted on AWS/GCP/Azure
     - Use managed RDS/Cloud SQL with Multi-AZ
     - Managed failover, no infrastructure to operate
   * - On-premises or private cloud, single site
     - **This guide** — single-DC HA cluster
     - Automatic failover within the datacenter, no cloud dependency
   * - On-premises, two or more sites, DR required
     - Single-DC HA (this guide) + Multi-DC DR guide (coming soon)
     - Active/warm-standby across datacenters

Requirements
~~~~~~~~~~~~

**Hardware (per node — minimum):**

- Operating system: Ubuntu 24.04 LTS
- CPU: 2 cores
- RAM: 4 GB
- Disk: 50 GB

**You need 3 nodes** and one spare IP address on the same subnet for the VIP.

**Network — ports that must be open between all three nodes:**

.. list-table::
   :widths: 15 85
   :header-rows: 1

   * - Port
     - Purpose
   * - 22
     - SSH (administration)
   * - 5432
     - PostgreSQL (replication, repmgr)
   * - 8008
     - pgchk.py health check (HAProxy → database nodes)
   * - VRRP (112)
     - Keepalived VIP election between nodes

**Ports that Mattermost application servers must reach:**

.. list-table::
   :widths: 15 85
   :header-rows: 1

   * - Port
     - Purpose
   * - 5000
     - Write connections (primary)
   * - 5001
     - Read connections (standbys)

**Software:** The following packages will be installed during setup. No
pre-installation is required.

- ``postgresql-17``
- ``postgresql-17-repmgr``
- ``haproxy``
- ``keepalived``
- ``python3`` (for pgchk.py)

Node planning worksheet
~~~~~~~~~~~~~~~~~~~~~~~

Complete this before starting. You will substitute these values throughout
the guide.

.. list-table::
   :widths: 15 25 25 35
   :header-rows: 1

   * - Node
     - Hostname
     - IP address
     - Initial role
   * - 1
     - pg1
     - _______________
     - Primary
   * - 2
     - pg2
     - _______________
     - Standby
   * - 3
     - pg3
     - _______________
     - Standby
   * - VIP
     - —
     - _______________
     - Floating (always points to primary)

**Subnet:** ``_______________`` (e.g. ``10.0.1.0``)

Time estimate
~~~~~~~~~~~~~

Allow **2–3 hours** for a first-time setup on pre-provisioned servers.
```

- [ ] **Step 4.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — before you begin / decision guidance section"
```

---

## Task 5: Write Section 3 — Setup Phase 1 (base installation)

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

Source: `docs/02-setup-guide.md` Phase 1

- [ ] **Step 5.1: Replace `[stub]` in Setup guide section with Phase 1 content**

Replace the `Setup guide` stub with:

```rst
Setup guide
-----------

.. note::

   Throughout this guide, substitute the IP addresses and subnet you recorded
   in the node planning worksheet above.

.. warning::

   Complete each phase in order. The checkpoint at the end of each phase must
   pass before you proceed.

Phase 1: Base installation (all nodes)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Run all steps in Phase 1 on **pg1, pg2, and pg3**.

**Step 1.1 — Configure /etc/hosts**

On each node, append to ``/etc/hosts``:

.. code-block:: text

   <PG1_IP>  pg1
   <PG2_IP>  pg2
   <PG3_IP>  pg3

Verify hostname resolution on each node:

.. code-block:: bash

   ping -c 1 pg1 && ping -c 1 pg2 && ping -c 1 pg3

Expected: 3 successful pings.

**Step 1.2 — Install PostgreSQL 17 and repmgr 5.5**

.. code-block:: bash

   sudo apt update
   sudo apt install -y curl ca-certificates
   sudo install -d /usr/share/postgresql-common/pgdg
   sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
       --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
   sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
       https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
       > /etc/apt/sources.list.d/pgdg.list'
   sudo apt update
   sudo apt install -y postgresql-17 postgresql-17-repmgr

✅ **Phase 1 checkpoint** — run on every node:

.. code-block:: bash

   sudo systemctl status postgresql | grep "active (running)"
   /usr/lib/postgresql/17/bin/repmgr --version

**Pass:** PostgreSQL shows ``active (running)``; repmgr prints ``repmgr 5.5.x``.

**Fail:** If PostgreSQL did not start, check ``journalctl -u postgresql`` for errors.
```

- [ ] **Step 5.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — setup Phase 1 (base install)"
```

---

## Task 6: Write Setup Phase 2 — PostgreSQL configuration

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

Source: `docs/02-setup-guide.md` Phase 2

- [ ] **Step 6.1: Append Phase 2 to the Setup guide section**

After the Phase 1 checkpoint block, add:

```rst
Phase 2: PostgreSQL configuration (all nodes)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Run all steps in Phase 2 on **pg1, pg2, and pg3**.

**Step 2.1 — Configure postgresql.conf**

Append to ``/etc/postgresql/17/main/postgresql.conf``:

.. code-block:: ini

   # Replication settings
   listen_addresses = '*'
   max_wal_senders = 10
   max_replication_slots = 10
   wal_level = replica
   hot_standby = on
   archive_mode = on
   archive_command = '/bin/true'
   shared_preload_libraries = 'repmgr'
   wal_log_hints = on
   wal_keep_size = 1024

**Step 2.2 — Configure pg_hba.conf**

Append to ``/etc/postgresql/17/main/pg_hba.conf``:

.. code-block:: text

   # repmgr access
   host    repmgr      repmgr      <SUBNET>/24     trust
   host    repmgr      repmgr      127.0.0.1/32    trust
   # Replication connections
   host    replication repmgr      <SUBNET>/24     trust
   host    replication repmgr      127.0.0.1/32    trust

.. note::

   For production, replace ``trust`` with ``scram-sha-256`` and configure
   ``.pgpass`` files on each node.

**Step 2.3 — Restart PostgreSQL**

.. code-block:: bash

   sudo systemctl restart postgresql

✅ **Phase 2 checkpoint** — run on every node:

.. code-block:: bash

   sudo -u postgres psql -c "SHOW wal_level;"
   sudo -u postgres psql -c "SHOW shared_preload_libraries;"

**Pass:** ``wal_level`` is ``replica``; ``shared_preload_libraries`` contains ``repmgr``.

**Fail:** If PostgreSQL did not restart, check ``journalctl -u postgresql``.
```

- [ ] **Step 6.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — setup Phase 2 (PostgreSQL config)"
```

---

## Task 7: Write Setup Phase 3 — repmgr configuration and standby clone

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

Source: `docs/02-setup-guide.md` Phase 3

- [ ] **Step 7.1: Append Phase 3 to the Setup guide section**

After the Phase 2 checkpoint block, add:

```rst
Phase 3: repmgr configuration and cluster initialisation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Step 3.1 — Create repmgr user and database (pg1 only)**

.. code-block:: bash

   sudo -u postgres createuser --superuser repmgr
   sudo -u postgres createdb --owner=repmgr repmgr
   sudo -u postgres psql -c "ALTER USER repmgr SET search_path TO repmgr, public;"

**Step 3.2 — Create /etc/repmgr.conf (all nodes)**

Create ``/etc/repmgr.conf`` on each node. Adjust ``node_id``, ``node_name``,
and ``host`` per node:

**pg1:**

.. code-block:: ini

   node_id=1
   node_name='pg1'
   conninfo='host=<PG1_IP> user=repmgr dbname=repmgr connect_timeout=2'
   data_directory='/var/lib/postgresql/17/main'
   use_replication_slots=yes
   monitoring_history=yes
   log_level=INFO
   pg_bindir='/usr/lib/postgresql/17/bin'
   service_start_command='sudo /usr/bin/pg_ctlcluster 17 main start'
   service_stop_command='sudo /usr/bin/pg_ctlcluster 17 main stop'
   service_restart_command='sudo /usr/bin/pg_ctlcluster 17 main restart'
   service_reload_command='sudo /usr/bin/pg_ctlcluster 17 main reload'
   service_promote_command='sudo /usr/bin/pg_ctlcluster 17 main promote'
   failover=automatic
   promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
   follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'
   reconnect_attempts=3
   reconnect_interval=5
   monitor_interval_secs=2

**pg2:** Same as above with ``node_id=2``, ``node_name='pg2'``, ``host=<PG2_IP>``.

**pg3:** Same as above with ``node_id=3``, ``node_name='pg3'``, ``host=<PG3_IP>``.

**Step 3.3 — Register primary (pg1 only)**

.. code-block:: bash

   sudo -u postgres repmgr -f /etc/repmgr.conf primary register

**Step 3.4 — Clone standbys (pg2 and pg3)**

Run on **pg2**, then **pg3**:

.. code-block:: bash

   sudo systemctl stop postgresql
   sudo -u postgres repmgr -h <PG1_IP> -U repmgr -d repmgr \
       -f /etc/repmgr.conf standby clone --delete-existing-pgdata
   sudo systemctl start postgresql
   sudo -u postgres repmgr -f /etc/repmgr.conf standby register

**Step 3.5 — Start repmgrd (all nodes)**

Create ``/etc/systemd/system/repmgrd.service``:

.. code-block:: ini

   [Unit]
   Description=repmgr daemon
   After=postgresql.service
   Requires=postgresql.service

   [Service]
   User=postgres
   ExecStart=/usr/lib/postgresql/17/bin/repmgrd -f /etc/repmgr.conf --no-daemonize
   Restart=on-failure

   [Install]
   WantedBy=multi-user.target

.. code-block:: bash

   sudo systemctl daemon-reload
   sudo systemctl enable repmgrd
   sudo systemctl start repmgrd

✅ **Phase 3 checkpoint** — run on any node:

.. code-block:: bash

   sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

**Pass:** Output shows all three nodes — pg1 as ``* running`` (primary), pg2 and
pg3 as ``running`` (standby). On pg1, the following query returns 2 rows:

.. code-block:: bash

   sudo -u postgres psql -c "SELECT client_addr, state FROM pg_stat_replication;"

**Fail:** A standby showing ``! running`` means replication did not establish.
Check ``journalctl -u postgresql`` on the failed standby. Common cause: firewall
blocking port 5432 between nodes.
```

- [ ] **Step 7.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — setup Phase 3 (repmgr + standby clone)"
```

---

## Task 8: Write Setup Phase 4 — HAProxy, pgchk.py, and Keepalived

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

Source: `docs/02-setup-guide.md` Phases 4–6

- [ ] **Step 8.1: Append Phase 4 to the Setup guide section**

After the Phase 3 checkpoint block, add:

```rst
Phase 4: HAProxy, health check, and VIP (all nodes)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Run all steps in Phase 4 on **pg1, pg2, and pg3**.

**Step 4.1 — Install HAProxy**

.. code-block:: bash

   sudo apt install -y haproxy

**Step 4.2 — Configure HAProxy**

Replace ``/etc/haproxy/haproxy.cfg``:

.. code-block:: text

   global
       log /dev/log local0
       maxconn 4000

   defaults
       log global
       mode tcp
       timeout connect 5s
       timeout client 30s
       timeout server 30s

   frontend pg_write
       bind *:5000
       default_backend pg_primary

   frontend pg_read
       bind *:5001
       default_backend pg_replicas

   backend pg_primary
       option tcp-check
       server pg1 <PG1_IP>:5432 check port 8008
       server pg2 <PG2_IP>:5432 check port 8008 backup
       server pg3 <PG3_IP>:5432 check port 8008 backup

   backend pg_replicas
       balance roundrobin
       option tcp-check
       server pg2 <PG2_IP>:5432 check port 8008
       server pg3 <PG3_IP>:5432 check port 8008
       server pg1 <PG1_IP>:5432 check port 8008 backup

**Step 4.3 — Deploy pgchk.py**

``pgchk.py`` is a lightweight HTTP server that returns ``200 OK`` when the local
node is the primary and ``503`` otherwise. HAProxy queries port 8008 on each
node to determine where to route connections.

Copy ``pgchk.py`` from the
`ha-postgres-reprmgr-haproxy repository <https://github.com/sadohert/ha-postgres-reprmgr-haproxy>`__
to ``/usr/local/bin/pgchk.py`` on each node and make it executable:

.. code-block:: bash

   sudo chmod +x /usr/local/bin/pgchk.py

Create ``/etc/systemd/system/pgchk.service``:

.. code-block:: ini

   [Unit]
   Description=PostgreSQL Health Check for HAProxy
   After=postgresql.service

   [Service]
   ExecStart=/usr/bin/python3 /usr/local/bin/pgchk.py --port 8008
   Restart=always

   [Install]
   WantedBy=multi-user.target

.. code-block:: bash

   sudo systemctl daemon-reload
   sudo systemctl enable pgchk
   sudo systemctl start pgchk
   sudo systemctl enable haproxy
   sudo systemctl start haproxy

**Step 4.4 — Install and configure Keepalived**

.. code-block:: bash

   sudo apt install -y keepalived

Create ``/etc/keepalived/keepalived.conf``. Set the ``priority`` field: pg1 gets
``101``, pg2 gets ``100``, pg3 gets ``99``. Set ``virtual_ipaddress`` to your VIP:

.. code-block:: text

   vrrp_instance VI_1 {
       state BACKUP
       interface eth0
       virtual_router_id 51
       priority 101
       advert_int 1
       nopreempt
       virtual_ipaddress {
           <CLUSTER_VIP>/24
       }
   }

.. code-block:: bash

   sudo systemctl enable keepalived
   sudo systemctl start keepalived

✅ **Phase 4 checkpoint** — run on any node:

.. code-block:: bash

   # VIP should be active on the primary node (pg1)
   ip addr show | grep <CLUSTER_VIP>

   # Port 5000 should connect to primary
   psql -h <CLUSTER_VIP> -p 5000 -U repmgr -d repmgr \
       -c "SELECT inet_server_addr(), pg_is_in_recovery();"

   # Port 5001 should connect to a standby
   psql -h <CLUSTER_VIP> -p 5001 -U repmgr -d repmgr \
       -c "SELECT inet_server_addr(), pg_is_in_recovery();"

**Pass:** VIP visible on pg1. Port 5000 returns ``pg_is_in_recovery = f`` (primary).
Port 5001 returns ``pg_is_in_recovery = t`` (standby).

**Fail:** If the VIP is not on pg1, check ``journalctl -u keepalived``. If HAProxy
is not routing correctly, check ``journalctl -u haproxy`` and verify pgchk.py
is responding: ``curl http://<PG1_IP>:8008`` should return HTTP 200.
```

- [ ] **Step 8.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — setup Phase 4 (HAProxy, pgchk, Keepalived)"
```

---

## Task 9: Write Setup Phase 5 — End-to-end validation

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

Source: `docs/06-failure-simulation.md`

- [ ] **Step 9.1: Append Phase 5 to the Setup guide section**

After the Phase 4 checkpoint block, add:

```rst
Phase 5: End-to-end validation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Run this phase after all four previous phases pass on all nodes. This confirms
the cluster behaves correctly under failure before you connect Mattermost.

**Step 5.1 — Confirm healthy starting state**

.. code-block:: bash

   sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

**Pass:** pg1 is ``* running`` (primary); pg2 and pg3 are ``running`` (standby).

**Step 5.2 — Simulate primary failure**

On **pg1**:

.. code-block:: bash

   sudo systemctl stop postgresql

Wait 30 seconds, then on **pg2** or **pg3**:

.. code-block:: bash

   sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

**Pass:** One of pg2 or pg3 is now ``* running`` (primary). pg1 shows as ``! running``
(unreachable — expected).

**Step 5.3 — Verify HAProxy and VIP followed the new primary**

.. code-block:: bash

   psql -h <CLUSTER_VIP> -p 5000 -U repmgr -d repmgr \
       -c "SELECT inet_server_addr(), pg_is_in_recovery();"

**Pass:** Returns the IP of the newly promoted node with ``pg_is_in_recovery = f``.

**Step 5.4 — Recover the old primary as a standby**

On **pg1**:

.. code-block:: bash

   sudo systemctl start postgresql
   sudo -u postgres repmgr -f /etc/repmgr.conf node rejoin \
       --force-rewind --config-files=postgresql.conf,pg_hba.conf

Then on any node:

.. code-block:: bash

   sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

**Pass:** All three nodes show ``running``; pg1 is now a standby.

.. note::

   Your cluster is ready for production. Connect Mattermost using the VIP
   address and port 5000 as the primary datasource. Optionally configure
   port 5001 as a read replica in ``config.json``.
```

- [ ] **Step 9.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — setup Phase 5 (end-to-end validation)"
```

---

## Task 10: Write Section 4 — Day-2 operations

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

Source: `docs/03-operations-guide.md`

- [ ] **Step 10.1: Replace `[stub]` in Day-2 operations section**

Replace the `Day-2 operations` stub with:

```rst
Day-2 operations
----------------

Check cluster status
~~~~~~~~~~~~~~~~~~~~

Run on any node:

.. code-block:: bash

   sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

Expected healthy output shows one ``* running`` primary and two ``running`` standbys.

Check replication lag
~~~~~~~~~~~~~~~~~~~~~

Run on the primary:

.. code-block:: bash

   sudo -u postgres psql -c "
   SELECT client_addr, application_name, state,
          pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS lag
   FROM pg_stat_replication;"

Normal lag is under 1 MB during steady state. Lag growing continuously
indicates a replication problem — check network connectivity and standby
PostgreSQL logs.

Controlled switchover (planned maintenance)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To move the primary role to a standby with zero data loss:

.. code-block:: bash

   # Run on the TARGET standby (e.g. pg2)
   sudo -u postgres repmgr -f /etc/repmgr.conf standby switchover

repmgr will demote the old primary and promote this node. The VIP and HAProxy
will follow automatically.

Add a standby node
~~~~~~~~~~~~~~~~~~

1. Provision a new server and complete Phases 1–2 of the setup guide.
2. Create ``/etc/repmgr.conf`` with the next available ``node_id``.
3. On the new node:

   .. code-block:: bash

      sudo systemctl stop postgresql
      sudo -u postgres repmgr -h <PRIMARY_IP> -U repmgr -d repmgr \
          -f /etc/repmgr.conf standby clone --delete-existing-pgdata
      sudo systemctl start postgresql
      sudo -u postgres repmgr -f /etc/repmgr.conf standby register

4. Add the new node to ``/etc/haproxy/haproxy.cfg`` on all existing nodes and
   reload HAProxy: ``sudo systemctl reload haproxy``.

Rejoin a failed node
~~~~~~~~~~~~~~~~~~~~

After recovering a failed standby:

.. code-block:: bash

   sudo -u postgres repmgr -f /etc/repmgr.conf node rejoin \
       --force-rewind --config-files=postgresql.conf,pg_hba.conf

After rejoining a failed primary (after automatic failover has already promoted
a new primary), run the same command on the old primary to re-register it as a
standby.
```

- [ ] **Step 10.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — day-2 operations section"
```

---

## Task 11: Write Section 5 — Troubleshooting

**Files:**
- Modify: `source/administration-guide/scale/postgres-ha-cluster.rst`

Source: `docs/04-troubleshooting-guide.md`

- [ ] **Step 11.1: Replace `[stub]` in Troubleshooting section**

Replace the `Troubleshooting` stub with:

```rst
Troubleshooting
---------------

repmgrd is not starting
~~~~~~~~~~~~~~~~~~~~~~~~

**Symptom:** ``systemctl status repmgrd`` shows ``failed`` or ``activating``.

**Likely cause:** PostgreSQL has not fully started yet, or the repmgr database
is not accessible.

**Resolution:**

.. code-block:: bash

   # Verify PostgreSQL is running first
   sudo systemctl status postgresql

   # Check repmgrd logs
   journalctl -u repmgrd -n 50

   # Test repmgr connection manually
   sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

Standby not replicating
~~~~~~~~~~~~~~~~~~~~~~~~

**Symptom:** ``repmgr cluster show`` shows a standby as ``! running``, or
``pg_stat_replication`` on the primary shows fewer than expected rows.

**Likely cause:** Network connectivity issue on port 5432, or ``pg_hba.conf``
not permitting the replication connection.

**Resolution:**

.. code-block:: bash

   # From the standby, test connectivity to the primary
   pg_isready -h <PRIMARY_IP> -p 5432 -U repmgr

   # Check PostgreSQL logs on the standby
   sudo -u postgres tail -50 /var/log/postgresql/postgresql-17-main.log

VIP not moving after failover
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Symptom:** After a primary failure and successful repmgr promotion, the VIP
remains on the failed node or does not appear on the new primary.

**Likely cause:** Keepalived is not running, or VRRP traffic is blocked by a
firewall.

**Resolution:**

.. code-block:: bash

   sudo systemctl status keepalived
   journalctl -u keepalived -n 50

   # Verify VRRP traffic is not blocked — check cloud security groups or
   # iptables rules for protocol 112 (VRRP)

HAProxy routing to wrong node
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Symptom:** Connections on port 5000 land on a standby (writes fail), or
port 5001 routes to the primary.

**Likely cause:** pgchk.py is not running or returning incorrect status.

**Resolution:**

.. code-block:: bash

   # Check health check response on each node
   curl -v http://<NODE_IP>:8008

   # Primary should return HTTP 200; standbys should return HTTP 503
   sudo systemctl status pgchk
   journalctl -u pgchk -n 30

Split-brain prevention
~~~~~~~~~~~~~~~~~~~~~~

repmgr's ``failover=automatic`` setting and ``reconnect_attempts=3`` with
``reconnect_interval=5`` provide a brief delay before promoting a standby.
This prevents promotion during transient network blips.

If you suspect a split-brain scenario (two nodes both believing they are
primary), **do not write to either node**. Check cluster status from a
third node and use ``repmgr node service --action=stop`` to fence the
unintended primary before recovering.
```

- [ ] **Step 11.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/postgres-ha-cluster.rst
git commit -m "docs: postgres-ha-cluster — troubleshooting section"
```

---

## Task 12: Update scaling-for-enterprise.rst (toctree entry)

**Files:**
- Modify: `source/administration-guide/scale/scaling-for-enterprise.rst`

- [ ] **Step 12.1: Add toctree entry and index section**

In `scaling-for-enterprise.rst`, find the `High availability` toctree entry:

```rst
    High availability </administration-guide/scale/high-availability-cluster-based-deployment>
```

Add the new entry immediately after it:

```rst
    PostgreSQL HA cluster </administration-guide/scale/postgres-ha-cluster>
```

Also find the `High availability` prose section (starts around line 30):

```rst
High availability
-----------------

A :doc:`high availability cluster-based deployment </administration-guide/scale/high-availability-cluster-based-deployment>` enables...
```

Add a new prose section immediately after that section's paragraph:

```rst
PostgreSQL high availability cluster
--------------------------------------

For self-hosted deployments on bare-metal or VMs, a
:doc:`PostgreSQL HA cluster </administration-guide/scale/postgres-ha-cluster>`
provides automatic database failover using repmgr, HAProxy, and Keepalived —
without requiring a managed database service.
```

- [ ] **Step 12.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/scaling-for-enterprise.rst
git commit -m "docs: add postgres-ha-cluster to scaling-for-enterprise toctree"
```

---

## Task 13: Update high-availability-cluster-based-deployment.rst (cross-link)

**Files:**
- Modify: `source/administration-guide/scale/high-availability-cluster-based-deployment.rst`

- [ ] **Step 13.1: Find and update the database DR disclaimer**

Find this sentence in `high-availability-cluster-based-deployment.rst` (around line 33):

```rst
This document doesn't cover the configuration of databases in terms of disaster recovery, however, you can refer to the `frequently asked questions (FAQ)`_ section for our recommendations.
```

Replace with:

```rst
This document doesn't cover the configuration of databases in terms of disaster
recovery. For self-hosted deployments requiring database-level HA, see
:doc:`PostgreSQL high availability cluster </administration-guide/scale/postgres-ha-cluster>`.
```

- [ ] **Step 13.2: Commit**

```bash
cd /Users/stu/development/mattermost-docs
git add source/administration-guide/scale/high-availability-cluster-based-deployment.rst
git commit -m "docs: cross-link to postgres-ha-cluster from HA cluster deployment page"
```

---

## Task 14: Full build verification and PR

**Files:** none (verification and PR creation only)

- [ ] **Step 14.1: Run full Sphinx build and check for errors**

```bash
cd /Users/stu/development/mattermost-docs
pipenv run sphinx-build -b html source build/html 2>&1 | grep -E "ERROR|WARNING" | grep -v "duplicate label\|nonlocal image"
```

**Pass:** No `ERROR` lines. Warnings about image URLs or duplicate labels in unrelated files are acceptable.

- [ ] **Step 14.2: Spot-check rendered output**

```bash
open build/html/administration-guide/scale/postgres-ha-cluster.html
open build/html/administration-guide/scale/scaling-for-enterprise.html
```

Verify: postgres-ha-cluster renders with all 5 sections visible. scaling-for-enterprise shows the new "PostgreSQL high availability cluster" entry in the left nav.

- [ ] **Step 14.3: Push branch**

```bash
cd /Users/stu/development/mattermost-docs
git push -u origin postgres-ha-cluster-guide
```

- [ ] **Step 14.4: Open PR**

```bash
gh pr create \
  --repo mattermost/mattermost-docs \
  --title "Add PostgreSQL HA cluster guide" \
  --body "$(cat <<'EOF'
## Summary

- Adds `source/administration-guide/scale/postgres-ha-cluster.rst` — a new guide for deploying a 3-node PostgreSQL HA cluster using repmgr, HAProxy, and Keepalived
- Updates `scaling-for-enterprise.rst` toctree and adds a prose entry
- Updates `high-availability-cluster-based-deployment.rst` to cross-link to the new page

## Why

The existing HA doc covers Mattermost app-layer clustering but explicitly does not cover database HA. Many self-hosted customers on bare-metal or VMs need a database-level HA guide. This fills that gap.

## Validation

All setup steps and checkpoint commands have been validated on Ubuntu 24.04 LTS, PostgreSQL 17, repmgr 5.5, HAProxy 2.8.

## Related

- Closes sadohert/ha-postgres-reprmgr-haproxy#13
- A companion Multi-DC disaster recovery guide is planned (sadohert/ha-postgres-reprmgr-haproxy#14) and will be submitted as a follow-up PR once DC2 failover testing is complete.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review

**Spec coverage check:**
- ✅ No edition badge — opening paragraph states works with any self-hosted edition
- ✅ File placement and toctree — Tasks 12 and 13
- ✅ Architecture overview — Task 3
- ✅ Decision guidance / Before you begin — Task 4 (decision table, requirements, node worksheet, time estimate)
- ✅ Requirements upfront, not scattered — Task 4 consolidates all requirements; phases only contain steps
- ✅ Phased setup with numbered phases and steps — Tasks 5–9, phases 1–5, steps as `1.1`, `2.1` etc.
- ✅ Pass/fail checkpoints at end of each phase — Tasks 5–9
- ✅ Day-2 operations — Task 10
- ✅ Troubleshooting (symptom-first) — Task 11
- ✅ End-to-end validation (failure simulation) — Task 9
- ✅ Cross-link from existing HA doc — Task 13
- ✅ Build verification — Task 14

**Placeholder scan:** No TBDs, TODOs, or "implement later" items found.

**Type/name consistency:** RST section underlines are consistent (`---` for top-level sections, `~~~` for subsections). All ``.. code-block::`` directives specify a language. Phase numbers (1–5) are consistent between the spec and tasks.
