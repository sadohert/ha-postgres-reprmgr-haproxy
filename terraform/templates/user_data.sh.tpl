#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Beginning HA Postgres Bootstrap..."

# --- 1. System Config ---
hostnamectl set-hostname ${hostname}
echo "127.0.0.1 ${hostname}" >> /etc/hosts

# Mount Data Volume
echo "Mounting Data Volume..."
# Wait for volume attachment
while [ ! -e /dev/nvme1n1 ]; do sleep 1; done
mkfs.xfs /dev/nvme1n1
mkdir -p /var/lib/postgresql
echo "/dev/nvme1n1 /var/lib/postgresql xfs defaults 0 0" >> /etc/fstab
mount -a
chown -R postgres:postgres /var/lib/postgresql

# Install Packages
apt-get update
apt-get install -y postgresql-17 postgresql-contrib postgresql-17-repmgr haproxy python3-pip awscli jq prometheus-node-exporter prometheus-postgres-exporter

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
host    repmgr          repmgr          10.0.0.0/16         trust
host    replication     repmgr          10.0.0.0/16         trust
host    all             all             10.0.0.0/16         md5
EOF

# --- 4. Peer Discovery & Role Logic ---
echo "waiting for peer discovery..."
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
INSTANCE_ID=`curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/instance-id`
REGION=`curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region`

# Tag this instance with NodeID for deterministic role selection
aws ec2 create-tags --resources $INSTANCE_ID --tags Key=NodeID,Value=${node_id} --region $REGION

NODE_ID=${node_id}

if [ "$NODE_ID" == "1" ]; then
    echo "I am PRIMARY (Node 1)."
    systemctl restart postgresql
    
    # Setup DB
    sudo -u postgres psql -c "CREATE USER repmgr WITH SUPERUSER ENCRYPTED PASSWORD '${repmgr_password}';"
    sudo -u postgres createdb repmgr -O repmgr
    sudo -u postgres psql -c "ALTER USER repmgr SET search_path TO repmgr, public;"
    
    # Create Monitoring User
    sudo -u postgres psql -c "CREATE USER postgres_exporter WITH PASSWORD '${monitor_password}';"
    sudo -u postgres psql -c "ALTER USER postgres_exporter SET SEARCH_PATH TO postgres_exporter,pg_catalog;"
    sudo -u postgres psql -c "GRANT CONNECT ON DATABASE postgres TO postgres_exporter;"
    sudo -u postgres psql -c "GRANT pg_monitor TO postgres_exporter;"

    
    # Register Repmgr
    cat > /etc/repmgr.conf <<EOF
node_id=1
node_name='pg1'
conninfo='host=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4) user=repmgr dbname=repmgr connect_timeout=2'
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
    echo "I am STANDBY (Node $NODE_ID). Waiting for Primary..."
    
    # Discovery Loop: Find Private IP of NodeID=1
    PRIMARY_IP=""
    while [ -z "$PRIMARY_IP" ]; do
      echo "Looking for Primary (NodeID=1)..."
      PRIMARY_IP=$(aws ec2 describe-instances --filters "Name=tag:NodeID,Values=1" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].PrivateIpAddress" --output text --region $REGION)
      sleep 5
    done
    
    echo "Found Primary at $PRIMARY_IP"
    
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
conninfo='host=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4) user=repmgr dbname=repmgr connect_timeout=2'
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
    systemctl start postgresql
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
# (Simplified: Inject pgchk.py similar to docs)
# ... code to download/create pgchk.py ...

echo "Bootstrap Complete!"
