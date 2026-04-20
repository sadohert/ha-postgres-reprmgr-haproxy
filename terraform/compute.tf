data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "primary" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.admin_key.key_name

  subnet_id                   = local.selected_subnets[0]
  vpc_security_group_ids      = [aws_security_group.db_nodes.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "pg1"
    Role = "postgres-node"
    NodeID = 1
  })

  iam_instance_profile = aws_iam_instance_profile.db_profile.name
  user_data_replace_on_change = true

  # Use gzip compression to stay under 16KB limit
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data.sh.tpl", {
    hostname        = "pg1"
    node_id         = 1
    primary_ip      = "127.0.0.1" # Not used on primary

    ssh_private_key = tls_private_key.cluster_ssh.private_key_openssh
    ssh_public_key  = tls_private_key.cluster_ssh.public_key_openssh
    repmgr_password = var.repmgr_password
    postgres_password = var.db_password
    monitor_password = var.monitor_password
    mm_password     = var.mm_password
    vpc_cidrs       = join(",", [for assoc in data.aws_vpc.default.cidr_block_associations : assoc.cidr_block])
  }))
}

resource "aws_instance" "standbys" {
  count = 2

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.admin_key.key_name

  subnet_id                   = local.selected_subnets[count.index + 1]
  vpc_security_group_ids      = [aws_security_group.db_nodes.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "pg${count.index + 2}"
    Role = "postgres-node"
    NodeID = count.index + 2
  })

  iam_instance_profile = aws_iam_instance_profile.db_profile.name
  user_data_replace_on_change = true

  # Use gzip compression to stay under 16KB limit
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data.sh.tpl", {
    hostname        = "pg${count.index + 2}"
    node_id         = count.index + 2
    primary_ip      = aws_instance.primary.private_ip

    ssh_private_key = tls_private_key.cluster_ssh.private_key_openssh
    ssh_public_key  = tls_private_key.cluster_ssh.public_key_openssh
    repmgr_password = var.repmgr_password
    postgres_password = var.db_password
    monitor_password = var.monitor_password
    mm_password     = var.mm_password
    vpc_cidrs       = join(",", [for assoc in data.aws_vpc.default.cidr_block_associations : assoc.cidr_block])
  }))
}

# --- DC2 Warm Standby Nodes ---

resource "aws_instance" "dc2_upstream" {
  count = var.dc2_enabled ? 1 : 0

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.admin_key.key_name

  subnet_id                   = local.selected_subnets[0]
  vpc_security_group_ids      = [aws_security_group.db_nodes.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name   = "pg4"
    Role   = "postgres-node"
    NodeID = 4
  })

  iam_instance_profile        = aws_iam_instance_profile.db_profile.name
  user_data_replace_on_change = true

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data_dc2.sh.tpl", {
    hostname         = "pg4"
    node_id          = 4
    upstream_node_ip = aws_instance.primary.private_ip
    upstream_node_id = 1
    hosts_entries    = join("\n", [
      "${aws_instance.primary.private_ip} pg1",
      "${aws_instance.standbys[0].private_ip} pg2",
      "${aws_instance.standbys[1].private_ip} pg3",
    ])

    ssh_private_key   = tls_private_key.cluster_ssh.private_key_openssh
    ssh_public_key    = tls_private_key.cluster_ssh.public_key_openssh
    repmgr_password   = var.repmgr_password
    postgres_password = var.db_password
    monitor_password  = var.monitor_password
    mm_password       = var.mm_password
    vpc_cidrs         = join(",", [for assoc in data.aws_vpc.default.cidr_block_associations : assoc.cidr_block])
  }))
}

resource "aws_instance" "dc2_standbys" {
  count = var.dc2_enabled ? 2 : 0

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.admin_key.key_name

  subnet_id                   = local.selected_subnets[count.index + 1]
  vpc_security_group_ids      = [aws_security_group.db_nodes.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name   = "pg${count.index + 5}"
    Role   = "postgres-node"
    NodeID = count.index + 5
  })

  iam_instance_profile        = aws_iam_instance_profile.db_profile.name
  user_data_replace_on_change = true

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data_dc2.sh.tpl", {
    hostname         = "pg${count.index + 5}"
    node_id          = count.index + 5
    upstream_node_ip = aws_instance.dc2_upstream[0].private_ip
    upstream_node_id = 4
    hosts_entries    = join("\n", [
      "${aws_instance.primary.private_ip} pg1",
      "${aws_instance.standbys[0].private_ip} pg2",
      "${aws_instance.standbys[1].private_ip} pg3",
      "${aws_instance.dc2_upstream[0].private_ip} pg4",
    ])

    ssh_private_key   = tls_private_key.cluster_ssh.private_key_openssh
    ssh_public_key    = tls_private_key.cluster_ssh.public_key_openssh
    repmgr_password   = var.repmgr_password
    postgres_password = var.db_password
    monitor_password  = var.monitor_password
    mm_password       = var.mm_password
    vpc_cidrs         = join(",", [for assoc in data.aws_vpc.default.cidr_block_associations : assoc.cidr_block])
  }))
}
