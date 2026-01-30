# PostgreSQL HA Setup Guide

This guide covers the complete setup of a 3-node PostgreSQL HA cluster with automatic failover.

## Prerequisites

### Infrastructure Requirements
- 3 Ubuntu 24.04 LTS servers (physical or virtual)
- Minimum 2 CPU cores, 4GB RAM, 50GB storage per node
- Network connectivity between all nodes on ports 22, 5432, 8008, 5000, 5001
- A free IP address for the VIP on the same subnet

### Node Information (Example)
| Node | Hostname | IP Address | Initial Role |
|------|----------|------------|--------------|
| 1 | pg1 | 192.168.87.54 | Primary |
| 2 | pg2 | 192.168.87.57 | Standby |
| 3 | pg3 | 192.168.87.66 | Standby |
| VIP | - | 192.168.87.100 | Floating |

---

## Phase 1: Base Installation (All Nodes)

### 1.1 Install PostgreSQL 17

```bash
# Add PostgreSQL APT repository
sudo apt install curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail \
    https://www.postgresql.org/media/keys/ACCC4CF8.asc

. /etc/os-release
sudo sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
    https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > \
    /etc/apt/sources.list.d/pgdg.list"

# Install packages
sudo apt update
sudo apt install -y postgresql-17 postgresql-contrib postgresql-17-repmgr
```

### 1.2 Configure Sudoers for PostgreSQL Control

Create `/etc/sudoers.d/postgres_ctl`:
```bash
sudo bash -c 'echo "postgres ALL=(ALL) NOPASSWD: /usr/bin/pg_ctlcluster" > /etc/sudoers.d/postgres_ctl'
sudo chmod 0440 /etc/sudoers.d/postgres_ctl
```

### 1.3 Configure SSH Access for postgres User

On each node, set up passwordless SSH for the postgres user:

```bash
# Switch to postgres user
sudo su - postgres

# Generate SSH key (accept defaults)
ssh-keygen -t ed25519 -N ""

# Copy public key to all other nodes
ssh-copy-id postgres@pg1
ssh-copy-id postgres@pg2
ssh-copy-id postgres@pg3

# Test connectivity
ssh postgres@pg1 hostname
ssh postgres@pg2 hostname
ssh postgres@pg3 hostname
```

---

## Phase 2: PostgreSQL Configuration (All Nodes)

### 2.1 Configure postgresql.conf

Append to `/etc/postgresql/17/main/postgresql.conf`:

```ini
# Replication settings
listen_addresses = '*'
max_wal_senders = 10
max_replication_slots = 10
wal_level = replica
hot_standby = on
archive_mode = on
archive_command = '/bin/true'
shared_preload_libraries = 'repmgr'

# Required for pg_rewind (faster node rejoin)
wal_log_hints = on
```

### 2.2 Configure pg_hba.conf

Append to `/etc/postgresql/17/main/pg_hba.conf`:

```
# Allow repmgr user database access
host    repmgr          repmgr          192.168.87.0/24         trust
host    repmgr          repmgr          127.0.0.1/32            trust

# Allow replication connections
host    replication     repmgr          192.168.87.0/24         trust
host    replication     repmgr          127.0.0.1/32            trust
```

> **Note**: For production, replace `trust` with `scram-sha-256` and configure `.pgpass` files.

### 2.3 Restart PostgreSQL

```bash
sudo systemctl restart postgresql
```

---

## Phase 3: repmgr Configuration

### 3.1 Create repmgr User and Database (PRIMARY ONLY - pg1)

```bash
sudo su - postgres
createuser --superuser repmgr
createdb --owner=repmgr repmgr
psql -c "ALTER USER repmgr SET search_path TO repmgr, public;"
```

### 3.2 Create repmgr.conf (All Nodes)

Create `/etc/repmgr.conf` on each node. Adjust `node_id`, `node_name`, and `host` for each node:

**pg1 (`/etc/repmgr.conf`):**
```ini
node_id=1
node_name='pg1'
conninfo='host=192.168.87.54 user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/postgresql/17/main'
use_replication_slots=yes
monitoring_history=yes
log_level=INFO

# Service commands
service_start_command='sudo /usr/bin/pg_ctlcluster 17 main start'
service_stop_command='sudo /usr/bin/pg_ctlcluster 17 main stop'
service_restart_command='sudo /usr/bin/pg_ctlcluster 17 main restart'
service_reload_command='sudo /usr/bin/pg_ctlcluster 17 main reload'
service_promote_command='sudo /usr/bin/pg_ctlcluster 17 main promote'

# Automatic failover settings
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'
reconnect_attempts=3
reconnect_interval=5
monitor_interval_secs=2
```

**pg2**: Change `node_id=2`, `node_name='pg2'`, `host=192.168.87.57`

**pg3**: Change `node_id=3`, `node_name='pg3'`, `host=192.168.87.66`

### 3.3 Register Primary (pg1 ONLY)

```bash
sudo -u postgres repmgr -f /etc/repmgr.conf primary register
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show
```

### 3.4 Clone and Register Standbys (pg2 and pg3)

On each standby node:

```bash
# Stop PostgreSQL
sudo systemctl stop postgresql

# Clone from primary
sudo -u postgres repmgr -h 192.168.87.54 -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone --force

# Start PostgreSQL
sudo systemctl start postgresql

# Register standby
sudo -u postgres repmgr -f /etc/repmgr.conf standby register
```

### 3.5 Verify Cluster

```bash
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show
```

Expected output:
```
 ID | Name | Role    | Status    | Upstream | Location | Priority | Timeline
----+------+---------+-----------+----------+----------+----------+----------
 1  | pg1  | primary | * running |          | default  | 100      | 1
 2  | pg2  | standby |   running | pg1      | default  | 100      | 1
 3  | pg3  | standby |   running | pg1      | default  | 100      | 1
```

### 3.6 Start repmgrd Daemon (All Nodes)

Create `/etc/systemd/system/repmgrd.service`:

```ini
[Unit]
Description=repmgr daemon
After=postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=postgres
ExecStart=/usr/bin/repmgrd -f /etc/repmgr.conf --daemonize=false
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable repmgrd
sudo systemctl start repmgrd
```

---

## Phase 4: Health Check Service (All Nodes)

### 4.1 Deploy pgchk.py

Copy `pgchk.py` to `/usr/local/bin/pgchk.py` and make executable:

```bash
sudo cp pgchk.py /usr/local/bin/pgchk.py
sudo chmod +x /usr/local/bin/pgchk.py
```

### 4.2 Create Systemd Service

Create `/etc/systemd/system/pgchk.service`:

```ini
[Unit]
Description=PostgreSQL Health Check for HAProxy
After=postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=postgres
ExecStart=/usr/bin/python3 /usr/local/bin/pgchk.py --port 8008
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable pgchk
sudo systemctl start pgchk
```

### 4.3 Verify Health Checks

```bash
# On primary
curl http://localhost:8008/master   # Should return "OK - Primary"
curl http://localhost:8008/replica  # Should return "Service Unavailable"

# On standby
curl http://localhost:8008/master   # Should return "Service Unavailable"
curl http://localhost:8008/replica  # Should return "OK - Replica"
```

---

## Phase 5: HAProxy Configuration (All Nodes)

### 5.1 Install HAProxy

```bash
sudo apt install -y haproxy
```

### 5.2 Configure HAProxy

Replace `/etc/haproxy/haproxy.cfg`:

```
global
    maxconn 100

defaults
    log global
    mode tcp
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

# Write traffic - routes to PRIMARY only
listen pg_write
    bind *:5000
    option httpchk GET /master
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg1 192.168.87.54:5432 maxconn 100 check port 8008
    server pg2 192.168.87.57:5432 maxconn 100 check port 8008
    server pg3 192.168.87.66:5432 maxconn 100 check port 8008

# Read traffic - routes to STANDBYs, falls back to PRIMARY if all standbys down
frontend pg_read_fe
    bind *:5001
    acl replicas_up nbsrv(pg_read_replicas) ge 1
    use_backend pg_read_replicas if replicas_up
    default_backend pg_read_fallback

backend pg_read_replicas
    balance leastconn
    option httpchk GET /replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg1 192.168.87.54:5432 maxconn 100 check port 8008
    server pg2 192.168.87.57:5432 maxconn 100 check port 8008
    server pg3 192.168.87.66:5432 maxconn 100 check port 8008

backend pg_read_fallback
    balance leastconn
    option httpchk GET /ready
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg1 192.168.87.54:5432 maxconn 100 check port 8008
    server pg2 192.168.87.57:5432 maxconn 100 check port 8008
    server pg3 192.168.87.66:5432 maxconn 100 check port 8008
```

**How the read fallback works:**
- `nbsrv(pg_read_replicas) ge 1` checks if at least one standby is available
- If yes, traffic routes to `pg_read_replicas` (standbys only)
- If no standbys are available, traffic falls back to `pg_read_fallback` (any healthy node including primary)

### 5.3 Enable and Start HAProxy

```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
```

---

## Phase 6: Keepalived Configuration (All Nodes)

### 6.1 Install Keepalived

```bash
sudo apt install -y keepalived
```

### 6.2 Identify Network Interface

```bash
ip route get 192.168.87.57 | head -1
# Note the interface name (e.g., enp0s2, eth0)
```

### 6.3 Create Notification Script (All Nodes)

Create `/etc/keepalived/notify.sh`:

```bash
#!/bin/bash
# Keepalived notification script - logs VIP state changes

STATE=$1
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOGFILE="/var/log/keepalived-notify.log"

case $STATE in
    "master") echo "$TIMESTAMP - $HOSTNAME - VIP ACQUIRED - Now MASTER" >> $LOGFILE ;;
    "backup") echo "$TIMESTAMP - $HOSTNAME - VIP RELEASED - Now BACKUP" >> $LOGFILE ;;
    "fault")  echo "$TIMESTAMP - $HOSTNAME - FAULT DETECTED" >> $LOGFILE ;;
esac

logger -t keepalived "$STATE - $HOSTNAME"
```

Make executable:
```bash
sudo chmod +x /etc/keepalived/notify.sh
```

### 6.4 Configure Keepalived

Create `/etc/keepalived/keepalived.conf` on each node. The configuration uses **unicast mode** for reliable operation in VMware/virtualized environments.

**pg1 (Priority 101):**
```
vrrp_script chk_haproxy {
    script "/usr/bin/curl -sf http://localhost:8008/ready"
    interval 2
    weight 2
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface enp0s2
    virtual_router_id 51
    priority 101
    advert_int 1
    nopreempt

    authentication {
        auth_type PASS
        auth_pass <STRONG_PASSWORD>
    }

    unicast_src_ip 192.168.87.54
    unicast_peer {
        192.168.87.57
        192.168.87.66
    }

    virtual_ipaddress {
        192.168.87.100
    }

    track_script {
        chk_haproxy
    }

    notify_master "/etc/keepalived/notify.sh master"
    notify_backup "/etc/keepalived/notify.sh backup"
    notify_fault  "/etc/keepalived/notify.sh fault"
}
```

**pg2 (Priority 100):** Change `priority 101` to `priority 100`, `unicast_src_ip` to `192.168.87.57`, and update `unicast_peer` to include `192.168.87.54` and `192.168.87.66`.

**pg3 (Priority 99):** Change `priority 101` to `priority 99`, `unicast_src_ip` to `192.168.87.66`, and update `unicast_peer` to include `192.168.87.54` and `192.168.87.57`.

**Key configuration choices:**
- **`state BACKUP` on all nodes**: Uses election-based selection instead of static master
- **`nopreempt`**: Prevents VIP from moving back to higher-priority node after recovery (reduces flapping)
- **Unicast mode**: More reliable than multicast in virtualized environments
- **Health check via `/ready`**: Verifies actual PostgreSQL connectivity, not just process existence

### 6.5 Enable and Start Keepalived

```bash
sudo systemctl enable keepalived
sudo systemctl start keepalived
```

### 6.6 Verify VIP

```bash
ip addr show | grep 192.168.87.100

# Check the notify log
sudo cat /var/log/keepalived-notify.log
```

---

## Phase 7: Validation

### 7.1 Test Write Connection via VIP

```bash
psql -h 192.168.87.100 -p 5000 -U repmgr -d repmgr \
    -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

Expected: Returns primary IP with `pg_is_in_recovery = f`

### 7.2 Test Read Connection via VIP

```bash
psql -h 192.168.87.100 -p 5001 -U repmgr -d repmgr \
    -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

Expected: Returns standby IP with `pg_is_in_recovery = t`

### 7.3 Test Automatic Failover

```bash
# On primary (pg1)
sudo systemctl stop postgresql

# Wait 20 seconds, then check cluster from another node
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

# Verify writes still work via VIP
psql -h 192.168.87.100 -p 5000 -U repmgr -d repmgr \
    -c "SELECT inet_server_addr();"
```

---

## Service Summary

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5432 | Database |
| pgchk.py | 8008 | Health check HTTP |
| HAProxy (write) | 5000 | Primary routing |
| HAProxy (read) | 5001 | Standby routing |
| Keepalived | VRRP | VIP management |
| repmgrd | - | Failover daemon |

---

## Phase 8: Monitoring Configuration (All Nodes)

### 8.1 Install Exporters
Execute on all database nodes (`pg1`, `pg2`, `pg3`):

```bash
# Install Prometheus Node Exporter (System Metrics)
sudo apt install -y prometheus-node-exporter

# Install Prometheus Postgres Exporter (DB Metrics)
sudo apt install -y prometheus-postgres-exporter
```

### 8.2 Configure Postgres Exporter
The exporter needs a user with monitoring privileges.

1.  **Create Monitoring User** (Execute on **Primary** only):
    ```bash
    sudo -u postgres psql -c "CREATE USER postgres_exporter PASSWORD 'password' IN ROLE pg_monitor;"
    ```

2.  **Configure Exporter** (Execute on **All Nodes**):
    Edit `/etc/default/prometheus-postgres-exporter`:
    ```ini
    DATA_SOURCE_NAME="postgresql://postgres_exporter:password@localhost:5432/postgres?sslmode=disable"
    ```

3.  **Restart Service**:
    ```bash
    sudo systemctl restart prometheus-postgres-exporter
    ```

### 8.3 Enable HAProxy Stats
To visualize HAProxy metrics, enable the statistics endpoint on each node.

Edit `/etc/haproxy/haproxy.cfg` and append to the `global` or `defaults` section, or add as a new listener:

```haproxy
listen stats
    bind *:8404
    stats enable
    stats uri /metrics
    stats refresh 10s
    stats admin if LOCAL
```

Restart HAProxy:
```bash
sudo systemctl restart haproxy
```

---

## Phase 9: Mattermost Configuration

### 9.1 Replica Lag Settings
To enable the "Replica Lag" panel in the Mattermost Performance Dashboard, configure `ReplicaLagSettings` in `config.json`. This should point to the **Write VIP** (`192.168.87.100`) so it can query the primary for replication status.

In `config.json` under `SqlSettings`:

```json
"ReplicaLagSettings": [
    {
        "DataSource": "postgres://mattermost:mattermost@192.168.87.100:5000/mattermost?sslmode=disable&connect_timeout=10",
        "QueryAbsoluteLag": "select usename, pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn) as metric from pg_stat_replication;",
        "QueryTimeLag": null
    }
]
```

> **Note**: This query calculates the byte lag between the current WAL LSN on the primary and the replay LSN of the replicas.

## Next Steps

- Review [Operations Guide](03-operations-guide.md) for day-to-day procedures
- Review [Troubleshooting Guide](04-troubleshooting-guide.md) for common issues
