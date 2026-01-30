# Mattermost + Monitoring Stack

Local development setup with Mattermost, Prometheus, and Grafana.

## Prerequisites

1. Docker and Docker Compose installed
2. PostgreSQL running locally with a database for Mattermost

## Quick Start

### 1. Prepare your PostgreSQL database

Create a database and user for Mattermost in your local PostgreSQL:

```sql
CREATE DATABASE mattermost;
CREATE USER mattermost WITH PASSWORD 'mattermost';
GRANT ALL PRIVILEGES ON DATABASE mattermost TO mattermost;
\c mattermost
GRANT ALL ON SCHEMA public TO mattermost;
```

### 2. Configure environment variables

```bash
cp .env.example .env
# Edit .env with your database credentials
```

### 3. Start the stack

```bash
cd monitoring
docker compose up -d
```

### 4. Access the services

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Mattermost | http://localhost:8065 | Create admin on first visit |
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | N/A |
| cAdvisor | http://localhost:8080 | N/A |

## Services Included

- **Mattermost** - Team messaging platform
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization and dashboards
- **postgres_exporter** - PostgreSQL metrics exporter
- **node_exporter** - Host system metrics
- **cAdvisor** - Docker container metrics

## Pre-configured Dashboards

Grafana comes with two dashboards:

1. **PostgreSQL Overview** - Database connections, tuple operations, cache hit ratio, database size
2. **System Overview** - CPU, memory, disk usage, container metrics, network I/O

## Monitoring Your HA PostgreSQL Setup

The `postgres_exporter` connects to your local PostgreSQL instance. To monitor your HA cluster:

1. If using HAProxy, update `prometheus/prometheus.yml` to add the HAProxy stats endpoint
2. The postgres_exporter will connect to whichever node your local port points to

## Stopping the Stack

```bash
docker compose down
```

To remove all data volumes:

```bash
docker compose down -v
```

## Troubleshooting

### Mattermost can't connect to database

1. Ensure PostgreSQL is running and accessible
2. Check that the database and user exist with proper permissions
3. Verify the credentials in `.env` match your PostgreSQL setup
4. On macOS/Windows, `host.docker.internal` should resolve to your host machine

### postgres_exporter shows no data

1. Ensure the postgres_exporter can reach your PostgreSQL
2. The user needs `pg_monitor` role or appropriate permissions:
   ```sql
   GRANT pg_monitor TO your_user;
   ```

### node_exporter not working on macOS

node_exporter requires Linux `/proc` and `/sys` filesystems. On macOS, it will have limited functionality. Use cAdvisor for container metrics instead.
