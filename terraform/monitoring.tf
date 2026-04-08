# --- Monitoring Node (Prometheus + Grafana) ---

resource "random_password" "grafana_admin_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "monitor_sg" {
  name        = "ha-postgres-monitor-sg"
  description = "Security group for Monitoring Node"
  vpc_id      = data.aws_vpc.default.id

  # SSH Access
  ingress {
    description = "SSH from Admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Grafana UI
  ingress {
    description = "Grafana Dashboard"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Prometheus UI (Optional, for debugging)
  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Loki Log Ingestion"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_vpc.default.cidr_block_associations : s.cidr_block]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "ha-postgres-monitor-sg"
  })
}

resource "aws_instance" "monitor" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small" # Slightly larger for Docker stack
  key_name      = aws_key_pair.admin_key.key_name

  subnet_id                   = local.selected_subnets[0] # Just put it in the first subnet
  vpc_security_group_ids      = [aws_security_group.monitor_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.db_profile.name # Re-use role for EC2 Discovery

  tags = merge(local.common_tags, {
    Name = "ha-postgres-monitor"
    Role = "monitor-node"
  })

  user_data = templatefile("${path.module}/templates/user_data_monitor.sh.tpl", {
    grafana_password = random_password.grafana_admin_password.result
  })
}

output "monitor_public_ip" {
  value = aws_instance.monitor.public_ip
}

# --- Dashboard Provisioning ---

resource "null_resource" "monitor_dashboards" {
  triggers = {
    instance_id = aws_instance.monitor.id
    dashboard_hash = filemd5("../monitoring/grafana/dashboards/ha_cluster.json") # Re-run if dash changes
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.admin_ssh.private_key_openssh
    host        = aws_instance.monitor.public_ip
  }

  # 1. Fix Permissions & Create Directories
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait > /dev/null", # Wait for User Data to finish (Docker install)
      "sudo mkdir -p /opt/monitoring/grafana/dashboards",
      "sudo mkdir -p /opt/monitoring/grafana/provisioning/dashboards",
      "sudo chown -R ubuntu:ubuntu /opt/monitoring" # Critical: Allow 'ubuntu' user to write files here
    ]
  }

  # 2. Upload JSON Dashboards
  provisioner "file" {
    source      = "../monitoring/grafana/dashboards/"
    destination = "/opt/monitoring/grafana/dashboards/"
  }

  # 3. Upload Provider Config
  provisioner "file" {
    source      = "../monitoring/grafana/provisioning/dashboards/dashboards.yml"
    destination = "/opt/monitoring/grafana/provisioning/dashboards/dashboards.yml"
  }

  # 4. Fix Docker Compose (Mount Dashboards) & Restart
  provisioner "remote-exec" {
    inline = [
      "cd /opt/monitoring",
      # Add volume mount to docker-compose if not present
      "grep -q '/var/lib/grafana/dashboards' docker-compose.yml || sed -i '/- .\\/grafana\\/provisioning:\\/etc\\/grafana\\/provisioning/a \\      - ./grafana/dashboards:/var/lib/grafana/dashboards' docker-compose.yml",
      "sudo docker compose down",
      "sudo docker compose up -d"
    ]
  }

  depends_on = [aws_instance.monitor]
}
