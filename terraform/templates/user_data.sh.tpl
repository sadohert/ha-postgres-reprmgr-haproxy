#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Beginning HA Postgres Bootstrap..."

# --- 1. System Config ---
hostnamectl set-hostname ${hostname}
echo "127.0.0.1 ${hostname}" >> /etc/hosts

# Add PostgreSQL Repository
apt-get update
apt-get install -y curl ca-certificates
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Install Packages and Setup Volume
echo "Installing and preparing volume..."

# Install Common Package first to get the user
apt-get update
apt-get install -y postgresql-common

# Mount Data Volume
while [ ! -e /dev/nvme1n1 ]; do sleep 1; done
mkfs.xfs -f /dev/nvme1n1
mkdir -p /var/lib/postgresql
echo "/dev/nvme1n1 /var/lib/postgresql xfs defaults 0 0" >> /etc/fstab
mount -a

# Ensure volume is clean for initdb
rm -rf /var/lib/postgresql/*
chown -R postgres:postgres /var/lib/postgresql

# Install everything else
# Specific version pinning to avoid pulling in default OS version (like 16)
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-17 postgresql-17-repmgr haproxy python3-pip jq prometheus-node-exporter prometheus-postgres-exporter

# Ensure cluster exists (sometimes initdb skips on pre-existing mount)
if ! pg_lsclusters | grep -q "^17[[:space:]]\+main"; then
    echo "Manually creating cluster..."
    pg_createcluster 17 main --start || echo "Cluster creation skipped or failed, continuing..."
fi

pip3 install awscli --break-system-packages
export PATH=$PATH:/usr/local/bin

# Configure Sudoers for Postgres (for Repmgr)
echo "postgres ALL=(ALL) NOPASSWD: /usr/bin/pg_ctlcluster" > /etc/sudoers.d/postgres

# Configure Postgres Exporter
cat > /etc/default/prometheus-postgres-exporter <<EOF
DATA_SOURCE_NAME="postgresql://postgres_exporter:${monitor_password}@localhost:5432/postgres?sslmode=disable"
EOF
systemctl restart prometheus-postgres-exporter


# --- 2. Secrets & SSH ---
echo "Configuring SSH..."
mkdir -p /var/lib/postgresql/.ssh
echo "${ssh_private_key}" > /var/lib/postgresql/.ssh/id_ed25519
echo "${ssh_public_key}" > /var/lib/postgresql/.ssh/id_ed25519.pub
cat /var/lib/postgresql/.ssh/id_ed25519.pub > /var/lib/postgresql/.ssh/authorized_keys
chmod 700 /var/lib/postgresql/.ssh
chmod 600 /var/lib/postgresql/.ssh/id_ed25519
chmod 644 /var/lib/postgresql/.ssh/id_ed25519.pub
chown -R postgres:postgres /var/lib/postgresql/.ssh

# Configure .pgpass for repmgr
echo "*:*:*:repmgr:${repmgr_password}" > /var/lib/postgresql/.pgpass
echo "*:*:replication:repmgr:${repmgr_password}" >> /var/lib/postgresql/.pgpass
chown postgres:postgres /var/lib/postgresql/.pgpass
chmod 600 /var/lib/postgresql/.pgpass

# --- 3. Postgres Configuration ---
echo "Configuring Postgres..."
PG_CONF="/etc/postgresql/17/main/postgresql.conf"
cat >> $PG_CONF <<EOF
listen_addresses = '*'
max_wal_senders = 10
max_replication_slots = 10
wal_level = replica
hot_standby = on
archive_mode = on
archive_command = '/bin/true'
shared_preload_libraries = 'repmgr'
wal_log_hints = on
EOF

HBA_CONF="/etc/postgresql/17/main/pg_hba.conf"
cat >> $HBA_CONF <<EOF
host    repmgr          repmgr          ${vpc_cidr}         trust
host    replication     repmgr          ${vpc_cidr}         trust
host    all             all             ${vpc_cidr}         md5
EOF

# --- 4. Role Logic ---
echo "Determining Role..."
NODE_ID=${node_id}
PRIMARY_IP="${primary_ip}"

if [ "$NODE_ID" == "1" ]; then
    echo "I am PRIMARY (Node 1)."
    systemctl restart postgresql
    
    # Wait for Postgres to be ready
    until pg_isready; do
      echo "Waiting for local Postgres..."
      sleep 2
    done
    
    # Setup DB
    sudo -u postgres psql -c "CREATE USER repmgr WITH SUPERUSER ENCRYPTED PASSWORD '${repmgr_password}';"
    sudo -u postgres createdb repmgr -O repmgr
    sudo -u postgres psql -c "ALTER USER repmgr SET search_path TO repmgr, public;"
    
    # Create Monitoring User
    sudo -u postgres psql -c "CREATE USER postgres_exporter WITH PASSWORD '${monitor_password}';"
    sudo -u postgres psql -c "ALTER USER postgres_exporter SET SEARCH_PATH TO postgres_exporter,pg_catalog;"
    sudo -u postgres psql -c "GRANT CONNECT ON DATABASE postgres TO postgres_exporter;"
    sudo -u postgres psql -c "GRANT pg_monitor TO postgres_exporter;"

    # Create Mattermost User & DB
    sudo -u postgres psql -c "CREATE USER mmuser WITH PASSWORD '${mm_password}';"
    sudo -u postgres psql -c "CREATE DATABASE mattermost OWNER mmuser;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE mattermost TO mmuser;"

    
    # Register Repmgr
    cat > /etc/repmgr.conf <<EOF
node_id=1
node_name='pg1'
conninfo='host=$(hostname -I | awk "{print \$1}") user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/postgresql/17/main'
use_replication_slots=yes
service_start_command='sudo /usr/bin/pg_ctlcluster 17 main start'
service_stop_command='sudo /usr/bin/pg_ctlcluster 17 main stop'
service_restart_command='sudo /usr/bin/pg_ctlcluster 17 main restart'
service_reload_command='sudo /usr/bin/pg_ctlcluster 17 main reload'
service_promote_command='sudo /usr/bin/pg_ctlcluster 17 main promote'
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'
EOF

    sudo -u postgres repmgr -f /etc/repmgr.conf primary register
    
else
    echo "I am STANDBY (Node $NODE_ID). Primay is at $PRIMARY_IP"
    
    # Poll for Primary availability
    while ! nc -z $PRIMARY_IP 5432; do   
      echo "Waiting for Postgres on $PRIMARY_IP..."
      sleep 5
    done
    
    systemctl stop postgresql
    rm -rf /var/lib/postgresql/17/main/*
    
    cat > /etc/repmgr.conf <<EOF
node_id=$NODE_ID
node_name='pg$NODE_ID'
conninfo='host=$(hostname -I | awk "{print \$1}") user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/postgresql/17/main'
use_replication_slots=yes
service_start_command='sudo /usr/bin/pg_ctlcluster 17 main start'
service_stop_command='sudo /usr/bin/pg_ctlcluster 17 main stop'
service_restart_command='sudo /usr/bin/pg_ctlcluster 17 main restart'
service_reload_command='sudo /usr/bin/pg_ctlcluster 17 main reload'
service_promote_command='sudo /usr/bin/pg_ctlcluster 17 main promote'
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'
EOF

    # Clone
    sudo -u postgres repmgr -h $PRIMARY_IP -U repmgr -d repmgr -f /etc/repmgr.conf standby clone --force

    # Wait for service to be active after clone
    systemctl restart postgresql
    until pg_isready; do
      echo "Waiting for replica Postgres..."
      sleep 2
    done

    sudo -u postgres repmgr -f /etc/repmgr.conf standby register
fi

# Enable Repmgrd
cat > /etc/systemd/system/repmgrd.service <<EOF
[Unit]
Description=repmgr daemon
After=postgresql.service
Requires=postgresql.service
[Service]
Type=simple
User=postgres
ExecStart=/usr/bin/repmgrd -f /etc/repmgr.conf --daemonize=false
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable repmgrd
systemctl start repmgrd

# --- 5. HAProxy & Health Check ---
echo "Deploying Health Check..."

# Create pgchk.py
cat > /usr/local/bin/pgchk.py <<'EOF'
#!/usr/bin/env python3
import sys
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
import argparse

DEFAULT_PORT = 8008
PG_USER = "postgres"
PG_DB = "postgres"
PG_PORT = "5432"

class PostgresHealthCheckHandler(BaseHTTPRequestHandler):
    def safe_write(self, data):
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def check_postgres_status(self):
        try:
            cmd = ["psql", "-U", PG_USER, "-d", PG_DB, "-p", PG_PORT, "-t", "-c", "SELECT pg_is_in_recovery();"]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if result.returncode != 0: return None
            output = result.stdout.strip()
            if output == 't': return True  # Standby
            elif output == 'f': return False # Primary
            return None
        except Exception: return None

    def do_GET(self):
        status = self.check_postgres_status()
        if status is None:
            self.send_response(503)
            self.end_headers()
            self.safe_write(b"PostgreSQL Unreachable\n")
            return
        is_standby = status
        is_primary = not status
        if self.path == '/master' or self.path == '/':
            if is_primary:
                self.send_response(200)
                self.end_headers()
                self.safe_write(b"OK - Primary\n")
            else:
                self.send_response(503)
                self.end_headers()
                self.safe_write(b"Service Unavailable - Not Primary\n")
        elif self.path == '/replica':
            if is_standby:
                self.send_response(200)
                self.end_headers()
                self.safe_write(b"OK - Replica\n")
            else:
                self.send_response(503)
                self.end_headers()
                self.safe_write(b"Service Unavailable - Not Replica\n")
        else:
            self.send_response(404)
            self.end_headers()
            self.safe_write(b"Not Found\n")

    def log_message(self, format, *args): pass

def run(server_class=HTTPServer, handler_class=PostgresHealthCheckHandler, port=DEFAULT_PORT):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    httpd.serve_forever()

if __name__ == '__main__':
    run()
EOF

chmod +x /usr/local/bin/pgchk.py

# Create pgchk Service
cat > /etc/systemd/system/pgchk.service <<EOF
[Unit]
Description=PostgreSQL Health Check for HAProxy
After=postgresql.service

[Service]
Type=simple
User=postgres
ExecStart=/usr/bin/python3 /usr/local/bin/pgchk.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pgchk
systemctl start pgchk

# Configure HAProxy
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

listen postgres_write
    bind *:5000
    option httpchk GET /master
    http-check expect status 200
    server pg_local 127.0.0.1:5432 check port 8008

listen postgres_read
    bind *:5001
    option httpchk GET /replica
    http-check expect status 200
    server pg_local 127.0.0.1:5432 check port 8008

frontend stats
    bind *:8404
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
    stats enable
    stats uri /stats
    stats refresh 10s

# Install Exporters
apt-get install -y prometheus-node-exporter prometheus-postgres-exporter

# Configure Postgres Exporter
cat > /etc/default/prometheus-postgres-exporter <<EOF
DATA_SOURCE_NAME="user=postgres host=/var/run/postgresql/ sslmode=disable"
EOF

systemctl restart prometheus-node-exporter
systemctl restart prometheus-postgres-exporter
EOF

systemctl restart haproxy

echo "Bootstrap Complete!"
