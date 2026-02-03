# --- Security Groups ---

resource "aws_security_group" "db_nodes" {
  name        = "ha-postgres-db-sg"
  description = "Security group for HA Postgres DB Nodes"
  vpc_id      = data.aws_vpc.default.id

  # SSH Access
  ingress {
    description      = "SSH from Admin"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = [var.admin_cidr]
  }

  # Internal SSH
  ingress {
    description      = "SSH from Internal Cluster"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    self             = true
  }

  # HAProxy Write Port
  ingress {
    description      = "HAProxy Write Port from Admin/External/AppServer"
    from_port        = 5000
    to_port          = 5000
    protocol         = "tcp"
    cidr_blocks      = concat([var.admin_cidr], [for s in data.aws_vpc.default.cidr_block_associations : s.cidr_block])
  }

  # HAProxy Read Port
  ingress {
    description      = "HAProxy Read Port from Admin/External/AppServer"
    from_port        = 5001
    to_port          = 5001
    protocol         = "tcp"
    cidr_blocks      = concat([var.admin_cidr], [for s in data.aws_vpc.default.cidr_block_associations : s.cidr_block])
  }

  # PostgreSQL Direct (for checking/monitoring)
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_vpc.default.cidr_block_associations : s.cidr_block]
  }

  # Health Checks
  ingress {
    description = "Health Check API from VPC"
    from_port   = 8008
    to_port     = 8008
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_vpc.default.cidr_block_associations : s.cidr_block]
  }
  
    # HAProxy Stats
  ingress {
    description = "HAProxy Stats from VPC"
    from_port   = 8404
    to_port     = 8404
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_vpc.default.cidr_block_associations : s.cidr_block]
  }

    # Node Exporter
  ingress {
    description = "Node Exporter from VPC"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_vpc.default.cidr_block_associations : s.cidr_block]
  }

  # --- Monitoring Access ---
  # Allow Monitor Node to scrape exporters
  ingress {
    description     = "Node Exporter from Monitor"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitor_sg.id]
  }

  ingress {
    description     = "Postgres Exporter from Monitor"
    from_port       = 9187
    to_port         = 9187
    protocol        = "tcp"
    security_groups = [aws_security_group.monitor_sg.id]
  }

  ingress {
    description     = "HAProxy Stats from Monitor"
    from_port       = 8404
    to_port         = 8404
    protocol        = "tcp"
    security_groups = [aws_security_group.monitor_sg.id]
  }

  # Internal Communication (Reciprocal)
  ingress {
    description = "Internal Cluster Communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Outbound Internet Access (for updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "ha-postgres-db-sg"
  })
}
