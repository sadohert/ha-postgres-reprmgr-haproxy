# PostgreSQL HA Quick Reference Card

## Connection Information

| Purpose | Host | Port |
|---------|------|------|
| **Writes (PRIMARY)** | 192.168.87.100 | 5000 |
| **Reads (STANDBY)** | 192.168.87.100 | 5001 |

```bash
# Write connection
psql -h 192.168.87.100 -p 5000 -U <user> -d <database>

# Read connection
psql -h 192.168.87.100 -p 5001 -U <user> -d <database>
```

---

## Daily Operations

### Check Cluster Status
```bash
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show
```

### Check Replication Lag
```bash
sudo -u postgres psql -c "SELECT client_addr,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes
    FROM pg_stat_replication;"
```

### Check VIP Location
```bash
ip addr show | grep 192.168.87.100

# View VIP state change history
sudo cat /var/log/keepalived-notify.log
```

### Check All Services
```bash
sudo systemctl status postgresql repmgrd pgchk haproxy keepalived
```

---

## Failover Commands

### Planned Switchover (from standby you want to promote)
```bash
sudo -u postgres repmgr standby switchover -f /etc/repmgr.conf --siblings-follow
```

### Manual Promote (emergency)
```bash
sudo -u postgres repmgr standby promote -f /etc/repmgr.conf --siblings-follow
```

### Rejoin Failed Node (using clone)
```bash
sudo systemctl stop postgresql
sudo -u postgres repmgr -h <PRIMARY_IP> -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone --force
sudo systemctl start postgresql
sudo -u postgres repmgr -f /etc/repmgr.conf standby register --force
```

### Rejoin Failed Node (using pg_rewind - faster)
```bash
sudo systemctl stop postgresql
sudo -u postgres repmgr node rejoin -f /etc/repmgr.conf \
    -d 'host=<PRIMARY_IP> dbname=repmgr user=repmgr' --force-rewind
```

---

## Service Management

### Restart Services (safe order)
```bash
sudo systemctl restart postgresql
sudo systemctl restart repmgrd
sudo systemctl restart pgchk
sudo systemctl restart haproxy
sudo systemctl restart keepalived
```

### View Logs
```bash
# PostgreSQL
sudo tail -f /var/log/postgresql/postgresql-17-main.log

# repmgrd
sudo journalctl -u repmgrd -f

# HAProxy
sudo journalctl -u haproxy -f

# Keepalived
sudo journalctl -u keepalived -f
```

---

## Health Check Endpoints

```bash
# Check if node is PRIMARY
curl http://localhost:8008/master

# Check if node is STANDBY
curl http://localhost:8008/replica

# Check if PostgreSQL is reachable (any role)
curl http://localhost:8008/ready
```

---

## Node Information

| Node | IP | Role | node_id |
|------|-----|------|---------|
| pg1 | 192.168.87.54 | varies | 1 |
| pg2 | 192.168.87.57 | varies | 2 |
| pg3 | 192.168.87.66 | varies | 3 |
| VIP | 192.168.87.100 | floating | - |

---

## Configuration Files

| File | Purpose |
|------|---------|
| `/etc/repmgr.conf` | repmgr configuration |
| `/etc/postgresql/17/main/postgresql.conf` | PostgreSQL settings |
| `/etc/postgresql/17/main/pg_hba.conf` | PostgreSQL authentication |
| `/etc/haproxy/haproxy.cfg` | HAProxy routing |
| `/etc/keepalived/keepalived.conf` | VIP management |

---

## Emergency Contacts

| Role | Contact |
|------|---------|
| DBA On-Call | _______________ |
| Infrastructure | _______________ |
| Application Team | _______________ |
