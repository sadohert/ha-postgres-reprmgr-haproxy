# PostgreSQL HA Troubleshooting Guide

This guide covers common issues, diagnostic procedures, and solutions.

---

## Diagnostic Commands

### Quick Health Check

```bash
# Cluster status
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

# Service status
sudo systemctl status postgresql repmgrd pgchk haproxy keepalived

# VIP location
ip addr show | grep 192.168.87.100

# Replication lag
sudo -u postgres psql -c "SELECT client_addr, state,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes
    FROM pg_stat_replication;"
```

### Log Locations

| Service | Log Location |
|---------|--------------|
| PostgreSQL | `/var/log/postgresql/postgresql-17-main.log` |
| repmgrd | `journalctl -u repmgrd` |
| HAProxy | `/var/log/haproxy.log` or `journalctl -u haproxy` |
| Keepalived | `journalctl -u keepalived` |
| pgchk | `journalctl -u pgchk` |

---

## Common Issues

### Issue: Node Shows as "unreachable" or "failed"

**Symptoms:**
```
 1  | pg1  | primary | ? unreachable | ...
```

**Possible Causes:**
1. PostgreSQL service is stopped
2. Network connectivity issue
3. pg_hba.conf blocking connections

**Diagnosis:**
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Test connectivity from another node
psql -h <NODE_IP> -U repmgr -d repmgr -c "SELECT 1;"

# Check network
ping <NODE_IP>
telnet <NODE_IP> 5432
```

**Solutions:**
```bash
# Start PostgreSQL if stopped
sudo systemctl start postgresql

# Check and fix pg_hba.conf
sudo cat /etc/postgresql/17/main/pg_hba.conf
sudo systemctl reload postgresql
```

---

### Issue: Standby Not Following Primary

**Symptoms:**
- Standby shows `? pg1` in Upstream column
- Replication lag increasing indefinitely

**Diagnosis:**
```bash
# On standby, check replication status
sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"

# Check if standby can connect to primary
psql -h <PRIMARY_IP> -U repmgr -d repmgr -c "SELECT 1;"
```

**Solutions:**

Option 1: Restart standby follow
```bash
sudo -u postgres repmgr standby follow -f /etc/repmgr.conf \
    --upstream-node-id=<PRIMARY_NODE_ID>
```

Option 2: Re-clone the standby
```bash
sudo systemctl stop postgresql
sudo -u postgres repmgr -h <PRIMARY_IP> -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone --force
sudo systemctl start postgresql
sudo -u postgres repmgr -f /etc/repmgr.conf standby register --force
```

---

### Issue: pg_rewind Fails

**Error:**
```
ERROR: target server needs to use either data checksums or "wal_log_hints = on"
```

**Cause:** `wal_log_hints` was not enabled before the divergence occurred.

**Solution:**
Use clone approach instead of pg_rewind:
```bash
sudo systemctl stop postgresql
sudo -u postgres repmgr -h <PRIMARY_IP> -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone --force
sudo systemctl start postgresql
sudo -u postgres repmgr -f /etc/repmgr.conf standby register --force
```

**Prevention:**
Ensure `wal_log_hints = on` is in `postgresql.conf` on all nodes before initial setup.

---

### Issue: repmgrd Not Starting or Exiting Immediately

**Symptoms:**
```
● repmgrd.service - repmgr daemon
   Active: active (exited)
```

**Cause:** Service file configured incorrectly; repmgrd daemonizing when it shouldn't.

**Solution:**
Update `/etc/systemd/system/repmgrd.service`:
```ini
[Service]
Type=simple
User=postgres
ExecStart=/usr/bin/repmgrd -f /etc/repmgr.conf --daemonize=false
```

Then:
```bash
sudo systemctl daemon-reload
sudo systemctl restart repmgrd
```

**Verify:**
```bash
pgrep -a repmgrd
```

---

### Issue: HAProxy Not Routing to Primary

**Symptoms:**
- Connections to port 5000 fail or go to wrong node
- Health checks failing

**Diagnosis:**
```bash
# Check pgchk service
sudo systemctl status pgchk

# Test health endpoint manually
curl http://localhost:8008/master

# Check HAProxy logs
sudo journalctl -u haproxy -n 50
```

**Solutions:**
```bash
# Restart pgchk if not running
sudo systemctl restart pgchk

# Restart HAProxy
sudo systemctl restart haproxy

# Verify configuration
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

---

### Issue: VIP Not Moving After Node Failure

**Symptoms:**
- VIP stuck on failed node
- Applications can't connect via VIP

**Diagnosis:**
```bash
# Check keepalived status
sudo systemctl status keepalived
sudo journalctl -u keepalived -n 50

# Check VRRP state
sudo journalctl -u keepalived | grep -i "state"

# Check VIP state change history
sudo cat /var/log/keepalived-notify.log

# Verify health check is working
curl -sf http://localhost:8008/ready && echo "Health check OK" || echo "Health check FAILED"

# Check unicast peer connectivity (if using unicast mode)
grep unicast_peer -A3 /etc/keepalived/keepalived.conf
ping -c 2 <PEER_IP>
```

**Common Causes:**
1. Health check script failing (`/ready` endpoint returning 503)
2. Unicast peers unreachable (firewall or network issue)
3. Interface name mismatch in configuration
4. Authentication password mismatch between nodes

**Solutions:**
```bash
# Restart keepalived on all nodes
sudo systemctl restart keepalived

# Check interface name matches configuration
ip link show
grep interface /etc/keepalived/keepalived.conf

# Verify authentication password matches on all nodes
sudo grep auth_pass /etc/keepalived/keepalived.conf

# Test the health check endpoint
curl -v http://localhost:8008/ready
```

---

### Issue: Split-Brain (Two Primaries)

**Symptoms:**
- `repmgr cluster show` shows two nodes as primary
- Applications writing to both nodes

**CRITICAL:** This can cause data loss. Act immediately.

**Diagnosis:**
```bash
# Check which node has more recent data
sudo -u postgres psql -c "SELECT pg_current_wal_lsn();"
```

**Resolution:**
1. Stop applications from writing
2. Identify the node with most recent/complete data
3. Demote the other node:
```bash
# On the node to demote
sudo systemctl stop postgresql

# Clone from the correct primary
sudo -u postgres repmgr -h <CORRECT_PRIMARY_IP> -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone --force

sudo systemctl start postgresql
sudo -u postgres repmgr -f /etc/repmgr.conf standby register --force
```

**Prevention:**
- Ensure proper network configuration
- Consider implementing fencing
- Use witness server for quorum

---

### Issue: High Replication Lag

**Symptoms:**
- `lag_bytes` in `pg_stat_replication` is high and growing

**Diagnosis:**
```bash
# Check standby I/O
iostat -x 1 5

# Check WAL sender/receiver
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"  # On standby

# Check network bandwidth
iperf3 -c <PRIMARY_IP>
```

**Solutions:**
```bash
# Increase wal_sender resources on primary
# postgresql.conf
max_wal_senders = 20

# Tune standby recovery
# postgresql.conf on standby
max_parallel_workers = 8
```

---

### Issue: Connection Refused on Port 5000/5001

**Symptoms:**
```
psql: error: connection to server failed: Connection refused
```

**Diagnosis:**
```bash
# Check if HAProxy is listening
sudo ss -tlnp | grep -E "5000|5001"

# Check HAProxy status
sudo systemctl status haproxy

# Check if backends are healthy
curl http://localhost:8008/master
```

**Solutions:**
```bash
# Start HAProxy if not running
sudo systemctl start haproxy

# Check for configuration errors
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Ensure pgchk is running
sudo systemctl restart pgchk
```

---

### Issue: Read Port (5001) Routing to Primary

**Symptoms:**
- Connections to port 5001 return `pg_is_in_recovery = f` (primary)
- Expected behavior when all standbys are unavailable

**This is expected behavior.** HAProxy is configured to fall back to the primary when all standbys are down (degraded mode).

**Diagnosis:**
```bash
# Check which backends are available
curl http://localhost:8008/replica  # Returns 503 on primary
curl http://localhost:8008/ready    # Returns 200 on any healthy node

# Verify standby status
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show
```

**To restore normal operation:**
1. Identify why standbys are down
2. Restart PostgreSQL on standby nodes
3. Verify standbys are healthy: `curl http://localhost:8008/replica`
4. HAProxy will automatically route reads back to standbys

---

### Issue: "could not connect to primary" During Clone

**Error:**
```
ERROR: unable to connect to primary server
```

**Diagnosis:**
```bash
# Test connection manually
psql -h <PRIMARY_IP> -U repmgr -d repmgr

# Check pg_hba.conf on primary
sudo cat /etc/postgresql/17/main/pg_hba.conf | grep repmgr
```

**Solutions:**

Update `pg_hba.conf` on primary to allow connections:
```
host    repmgr          repmgr          192.168.87.0/24         trust
host    replication     repmgr          192.168.87.0/24         trust
```

Then reload:
```bash
sudo systemctl reload postgresql
```

---

### Issue: Automatic Failover Not Triggering

**Symptoms:**
- Primary is down but no standby promoted
- repmgrd running but not acting

**Diagnosis:**
```bash
# Check repmgrd logs
sudo journalctl -u repmgrd -f

# Check repmgr.conf settings
grep -E "failover|reconnect" /etc/repmgr.conf
```

**Common causes:**
1. `failover=automatic` not set
2. `promote_command` or `follow_command` misconfigured
3. SSH connectivity issues between nodes

**Solutions:**

Verify `/etc/repmgr.conf`:
```ini
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'
reconnect_attempts=3
reconnect_interval=5
```

Restart repmgrd:
```bash
sudo systemctl restart repmgrd
```

---

## Recovery Procedures

### Complete Cluster Recovery

If the entire cluster is in a bad state:

1. **Stop all services on all nodes:**
```bash
sudo systemctl stop repmgrd haproxy keepalived
sudo systemctl stop postgresql
```

2. **Identify the node with most recent data:**
```bash
# Check pg_control on each node
sudo -u postgres /usr/lib/postgresql/17/bin/pg_controldata \
    /var/lib/postgresql/17/main | grep -E "Latest checkpoint|TimeLineID"
```

3. **Start that node as primary:**
```bash
sudo systemctl start postgresql
sudo -u postgres repmgr -f /etc/repmgr.conf primary register --force
```

4. **Clone other nodes from the primary:**
```bash
# On each standby
sudo -u postgres repmgr -h <PRIMARY_IP> -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone --force
sudo systemctl start postgresql
sudo -u postgres repmgr -f /etc/repmgr.conf standby register --force
```

5. **Start all services:**
```bash
sudo systemctl start repmgrd haproxy keepalived
```

---

## Preventive Measures

### Monitoring Checklist

Set up alerts for:
- [ ] Replication lag > 1MB
- [ ] Node unreachable
- [ ] VIP not responding
- [ ] HAProxy backend down
- [ ] Disk space < 20%
- [ ] repmgrd not running

### Regular Testing

- [ ] Monthly: Test manual failover in non-production
- [ ] Quarterly: Test automatic failover
- [ ] Semi-annually: Full disaster recovery test

### Documentation

- [ ] Keep IP addresses and credentials updated
- [ ] Document any customizations
- [ ] Maintain runbook for common scenarios

---

## Getting Help

### Information to Collect

When seeking support, gather:

```bash
# Cluster status
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show

# Recent events
sudo -u postgres repmgr -f /etc/repmgr.conf cluster event --limit=20

# Service status
sudo systemctl status postgresql repmgrd haproxy keepalived pgchk

# PostgreSQL logs (last 100 lines)
sudo tail -100 /var/log/postgresql/postgresql-17-main.log

# repmgrd logs
sudo journalctl -u repmgrd --since "1 hour ago"

# Configuration files
cat /etc/repmgr.conf
cat /etc/haproxy/haproxy.cfg
cat /etc/keepalived/keepalived.conf
```

### Resources

- [repmgr Documentation](https://repmgr.org/docs/current/)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)
- [HAProxy Documentation](https://www.haproxy.org/documentation/)
- [Keepalived Documentation](https://www.keepalived.org/manpage.html)
