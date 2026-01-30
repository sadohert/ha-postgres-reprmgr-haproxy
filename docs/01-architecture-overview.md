# PostgreSQL High Availability Architecture Overview

## Introduction

This document describes a highly available PostgreSQL deployment using **repmgr** for replication management and automatic failover, **HAProxy** for connection routing, and **Keepalived** for Virtual IP (VIP) management.

## Architecture Diagram

```
                         VIP: 192.168.87.100
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
         │192.168.87.54│ │192.168.87.57│ │192.168.87.66│
         └─────────────┘ └─────────────┘ └─────────────┘
```

## Components

### PostgreSQL 17
- **Role**: Primary database engine
- **Replication**: Streaming replication with replication slots
- **Configuration**: `wal_level=replica`, `hot_standby=on`

### repmgr 5.5
- **Role**: Replication manager and failover coordinator
- **Features**:
  - Cluster monitoring via `repmgrd` daemon
  - Automatic failover detection and promotion
  - Standby cloning and registration
  - Node rejoin capabilities

### HAProxy 2.8
- **Role**: TCP load balancer and connection router
- **Ports**:
  - `5000` - Write traffic (routes to PRIMARY only)
  - `5001` - Read traffic (routes to STANDBYs, load balanced)
- **Health Checks**: HTTP checks against pgchk.py on port 8008

### pgchk.py
- **Role**: PostgreSQL health check HTTP server
- **Port**: 8008
- **Endpoints**:
  - `/master` - Returns 200 if node is PRIMARY, 503 otherwise
  - `/replica` - Returns 200 if node is STANDBY, 503 otherwise
  - `/ready` - Returns 200 if PostgreSQL is reachable (any role), 503 otherwise

### Keepalived
- **Role**: Virtual IP (VIP) management using VRRP
- **VIP**: 192.168.87.100
- **Mode**: Unicast (recommended for VMware/virtualized environments)
- **Failover**: VIP moves to healthy node if current holder fails
- **Health Check**: Uses `/ready` endpoint to verify PostgreSQL connectivity
- **Notification**: Logs VIP state changes to `/var/log/keepalived-notify.log`

## Connection Endpoints

| Purpose | Address | Port | Description |
|---------|---------|------|-------------|
| **Writes** | 192.168.87.100 | 5000 | Always routes to PRIMARY |
| **Reads** | 192.168.87.100 | 5001 | Load balanced across STANDBYs (falls back to PRIMARY if all standbys down) |
| **Direct pg1** | 192.168.87.54 | 5432 | Direct connection (not recommended) |
| **Direct pg2** | 192.168.87.57 | 5432 | Direct connection (not recommended) |
| **Direct pg3** | 192.168.87.66 | 5432 | Direct connection (not recommended) |

## High Availability Features

### Automatic Failover
When the PRIMARY node fails:
1. `repmgrd` detects the failure after 3 reconnect attempts (15 seconds)
2. A STANDBY is automatically promoted to PRIMARY
3. Other STANDBYs reconfigure to follow the new PRIMARY
4. HAProxy health checks detect the change and route writes to the new PRIMARY
5. Applications connected via VIP:5000 automatically connect to the new PRIMARY

### Read Scaling
- Read traffic on port 5001 is distributed across STANDBY nodes
- Uses `leastconn` algorithm for load balancing
- **Degraded mode fallback**: If all STANDBYs are unavailable, read traffic automatically falls back to the PRIMARY to maintain availability

### VIP Failover
- If the node holding the VIP fails, Keepalived moves VIP to another healthy node
- Applications using the VIP experience minimal disruption
- All nodes run HAProxy, so any node can serve as the entry point

## Data Flow

### Write Operations (Port 5000)
```
Application → VIP:5000 → HAProxy → pgchk /master check → PRIMARY:5432
```

### Read Operations (Port 5001)
```
Application → VIP:5001 → HAProxy → pgchk /replica check → STANDBY:5432
```

## Recovery Time Objectives

| Scenario | Expected Recovery Time |
|----------|----------------------|
| Primary failure (automatic failover) | ~15-20 seconds |
| Standby failure | No impact to writes, reduced read capacity |
| HAProxy failure on VIP holder | ~3 seconds (Keepalived failover) |
| Network partition | Depends on configuration |

## Limitations

1. **No automatic fencing**: Split-brain prevention relies on proper network configuration
2. **Single VIP**: All traffic routes through one node's HAProxy
3. **Asynchronous replication**: Small data loss possible during failover (typically < 1 second of transactions)
4. **No connection pooling**: Consider adding PgBouncer for high-connection workloads

## Related Documentation

- [Setup Guide](02-setup-guide.md) - Installation and configuration steps
- [Operations Guide](03-operations-guide.md) - Day-to-day operations and maintenance
- [Troubleshooting Guide](04-troubleshooting-guide.md) - Common issues and solutions
