# PostgreSQL HA Operations Guide

This guide covers day-to-day operations, maintenance procedures, and common administrative tasks.

---

## Monitoring

### Check Cluster Status

```bash
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show
```

**Healthy output:**
```
 ID | Name | Role    | Status    | Upstream | Location | Priority | Timeline
----+------+---------+-----------+----------+----------+----------+----------
 1  | pg1  | primary | * running |          | default  | 100      | 1
 2  | pg2  | standby |   running | pg1      | default  | 100      | 1
 3  | pg3  | standby |   running | pg1      | default  | 100      | 1
```

### Check Replication Lag

On the PRIMARY:
```bash
sudo -u postgres psql -c "
SELECT
    client_addr,
    state,
    sent_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;"
```

### Check VIP Location

```bash
for node in pg1 pg2 pg3; do
    echo -n "$node: "
    ssh $node "ip addr show | grep 192.168.87.100" 2>/dev/null || echo "no VIP"
done
```

### Check VIP History (Keepalived Notify Log)

```bash
# View VIP state change history
sudo cat /var/log/keepalived-notify.log

# Follow VIP changes in real-time
sudo tail -f /var/log/keepalived-notify.log
```

### Check Service Status

```bash
# On each node
sudo systemctl status postgresql
sudo systemctl status repmgrd
sudo systemctl status pgchk
sudo systemctl status haproxy
sudo systemctl status keepalived
```

### Check HAProxy Backend Status

```bash
# Test which node responds as primary
curl -s http://localhost:8008/master

# Test which nodes respond as replica
curl -s http://localhost:8008/replica
```

---

## Planned Maintenance

### Planned Switchover (Zero Downtime)

Use switchover for planned maintenance. This gracefully demotes the current primary and promotes a standby.

**From the STANDBY you want to promote (e.g., pg2):**

```bash
# Dry run first
sudo -u postgres repmgr standby switchover -f /etc/repmgr.conf \
    --siblings-follow --dry-run

# Execute switchover
sudo -u postgres repmgr standby switchover -f /etc/repmgr.conf \
    --siblings-follow
```

**What happens:**
1. Current primary (pg1) is gracefully stopped
2. Standby (pg2) is promoted to primary
3. Other standbys (pg3) follow the new primary
4. Old primary (pg1) becomes a standby
5. HAProxy automatically routes traffic to new primary

### Switchover Back to Original Primary

Repeat the switchover from the node you want to become primary:

```bash
# From pg1 (now a standby)
sudo -u postgres repmgr standby switchover -f /etc/repmgr.conf \
    --siblings-follow
```

---

## Failover Handling

### Automatic Failover (repmgrd)

When automatic failover occurs, `repmgrd` handles:
1. Detecting primary failure (after `reconnect_attempts` × `reconnect_interval`)
2. Promoting the most suitable standby
3. Reconfiguring other standbys to follow the new primary

**Monitor failover events:**
```bash
sudo journalctl -u repmgrd -f
```

### Manual Failover

If `repmgrd` is not running or you need manual control:

```bash
# From the standby you want to promote
sudo -u postgres repmgr standby promote -f /etc/repmgr.conf \
    --siblings-follow
```

### Rejoin a Failed Node

After a node has been marked as failed, rejoin it to the cluster:

**Option 1: Using pg_rewind (faster, requires wal_log_hints=on)**
```bash
# On the failed node
sudo systemctl stop postgresql

sudo -u postgres repmgr node rejoin -f /etc/repmgr.conf \
    -d 'host=<NEW_PRIMARY_IP> dbname=repmgr user=repmgr' \
    --force-rewind
```

**Option 2: Using clone (always works, but slower)**
```bash
# On the failed node
sudo systemctl stop postgresql

# Clone from current primary
sudo -u postgres repmgr -h <NEW_PRIMARY_IP> -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone --force

# Start PostgreSQL
sudo systemctl start postgresql

# Re-register as standby
sudo -u postgres repmgr -f /etc/repmgr.conf standby register --force
```

---

## Adding a New Node

### 1. Prepare the New Node

Install PostgreSQL 17, repmgr, and configure according to [Setup Guide](02-setup-guide.md) Phase 1-2.

### 2. Create repmgr.conf

Use a unique `node_id` (e.g., 4) and configure with the new node's IP.

### 3. Clone from Primary

```bash
sudo systemctl stop postgresql

sudo -u postgres repmgr -h <PRIMARY_IP> -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone

sudo systemctl start postgresql
```

### 4. Register the Standby

```bash
sudo -u postgres repmgr -f /etc/repmgr.conf standby register
```

### 5. Update HAProxy Configuration

Add the new node to `/etc/haproxy/haproxy.cfg` on ALL nodes:

```
    server pg4 <NEW_NODE_IP>:5432 maxconn 100 check port 8008
```

Reload HAProxy:
```bash
sudo systemctl reload haproxy
```

### 6. Start repmgrd

```bash
sudo systemctl start repmgrd
```

---

## Removing a Node

### 1. Unregister the Node

On the node being removed:
```bash
sudo -u postgres repmgr standby unregister -f /etc/repmgr.conf
```

Or from another node:
```bash
sudo -u postgres repmgr standby unregister -f /etc/repmgr.conf --node-id=<NODE_ID>
```

### 2. Stop Services

```bash
sudo systemctl stop repmgrd
sudo systemctl stop postgresql
sudo systemctl stop pgchk
sudo systemctl stop haproxy
sudo systemctl stop keepalived
```

### 3. Update HAProxy on Remaining Nodes

Remove the node from `/etc/haproxy/haproxy.cfg` and reload:
```bash
sudo systemctl reload haproxy
```

### 4. Clean Up Replication Slot (Optional)

On the primary:
```bash
sudo -u postgres psql -c "SELECT pg_drop_replication_slot('repmgr_slot_<NODE_ID>');"
```

---

## PostgreSQL Upgrades

### Minor Version Upgrades (e.g., 17.1 → 17.2)

Minor upgrades are straightforward and can be done with minimal downtime.

**Rolling upgrade (one node at a time):**

```bash
# 1. Start with standbys
# On standby node:
sudo systemctl stop repmgrd
sudo apt update && sudo apt upgrade postgresql-17
sudo systemctl start repmgrd

# 2. Switchover to an upgraded standby
# From upgraded standby:
sudo -u postgres repmgr standby switchover -f /etc/repmgr.conf --siblings-follow

# 3. Upgrade the old primary (now a standby)
sudo systemctl stop repmgrd
sudo apt update && sudo apt upgrade postgresql-17
sudo systemctl start repmgrd
```

### Major Version Upgrades (e.g., 17 → 18)

Major upgrades require more planning. Options:

**Option A: pg_upgrade with downtime**
1. Stop all services
2. Run `pg_upgrade` on primary
3. Rebuild standbys via clone
4. Start services

**Option B: Logical replication (minimal downtime)**
1. Set up new cluster on PostgreSQL 18
2. Configure logical replication from old to new
3. Switch applications to new cluster
4. Decommission old cluster

---

## HAProxy Maintenance

### Reload Configuration (No Downtime)

```bash
sudo systemctl reload haproxy
```

### Check HAProxy Status

```bash
sudo systemctl status haproxy

# Check which backends are healthy
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock
```

### Temporarily Remove a Node from Pool

Edit `/etc/haproxy/haproxy.cfg` and add `disabled` to the server line:
```
    server pg2 192.168.87.57:5432 maxconn 100 check port 8008 disabled
```

Then reload:
```bash
sudo systemctl reload haproxy
```

---

## Backup and Recovery

### Configure Continuous Archiving

Update `postgresql.conf` on PRIMARY:
```ini
archive_command = 'cp %p /var/lib/postgresql/archive/%f'
```

Create archive directory:
```bash
sudo mkdir -p /var/lib/postgresql/archive
sudo chown postgres:postgres /var/lib/postgresql/archive
```

### Take a Base Backup

```bash
sudo -u postgres pg_basebackup -D /var/lib/postgresql/backup \
    -Ft -z -P -X stream
```

### Point-in-Time Recovery

1. Stop PostgreSQL
2. Restore base backup
3. Create `recovery.signal` file
4. Configure `restore_command` in `postgresql.conf`
5. Start PostgreSQL

---

## Security Hardening

### Replace Trust Authentication

Update `pg_hba.conf` to use password authentication:
```
host    repmgr          repmgr          192.168.87.0/24         scram-sha-256
host    replication     repmgr          192.168.87.0/24         scram-sha-256
```

Create `.pgpass` file on each node (`/var/lib/postgresql/.pgpass`):
```
*:5432:repmgr:repmgr:<PASSWORD>
*:5432:replication:repmgr:<PASSWORD>
```

Set permissions:
```bash
chmod 600 /var/lib/postgresql/.pgpass
```

### Update Keepalived Authentication

Change the default password in `/etc/keepalived/keepalived.conf`:
```
authentication {
    auth_type PASS
    auth_pass <STRONG_PASSWORD>
}
```

---

## Regular Maintenance Tasks

### Daily
- Check replication lag
- Verify all nodes are healthy
- Review PostgreSQL and repmgrd logs

### Weekly
- Test failover in non-production environment
- Review and rotate logs
- Check disk space

### Monthly
- Test backup restoration
- Review and update documentation
- Verify monitoring alerts work

### Quarterly
- Apply security patches
- Review and optimize PostgreSQL configuration
- Capacity planning review

---

## Useful Commands Reference

| Task | Command |
|------|---------|
| Cluster status | `sudo -u postgres repmgr cluster show` |
| Node status | `sudo -u postgres repmgr node status` |
| Check events | `sudo -u postgres repmgr cluster event` |
| Replication lag | `sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"` |
| Promote standby | `sudo -u postgres repmgr standby promote --siblings-follow` |
| Switchover | `sudo -u postgres repmgr standby switchover --siblings-follow` |
| Rejoin node | `sudo -u postgres repmgr node rejoin -d 'host=... user=repmgr'` |
| Clone standby | `sudo -u postgres repmgr standby clone -h <PRIMARY> --force` |
| Register standby | `sudo -u postgres repmgr standby register --force` |

---

## Next Steps

- Review [Troubleshooting Guide](04-troubleshooting-guide.md) for common issues
- Set up monitoring and alerting (Prometheus, Grafana, etc.)
- Configure automated backups to offsite storage
