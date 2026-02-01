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

resource "aws_instance" "db_nodes" {
  count = 3

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.admin_key.key_name # Ensure key exists before instance

  subnet_id                   = data.aws_subnets.default.ids[count.index]
  
  # Removed static private_ip assignment to avoid subnet mismatches.
  # Discovery script uses Tags to find IPs dynamically.
  # Reverting private_ip attempt. The script uses AWS CLI to find Primary by Tag.
  
  vpc_security_group_ids      = [aws_security_group.db_nodes.id]
  associate_public_ip_address = true # Simplification: Use public IPs in Default VPC

  # Root volume
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "pg${count.index + 1}"
    Role = "postgres-node"
  }

  iam_instance_profile = aws_iam_instance_profile.db_profile.name

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    hostname        = "pg${count.index + 1}"
    node_id         = count.index + 1
    # The script uses AWS CLI tag discovery, so primary_ip variable is a fallback or needs to be dynamic.
    # We will let the script discover "NodeID=1" IP.
    primary_ip      = "" 
    
    ssh_private_key = tls_private_key.cluster_ssh.private_key_openssh
    ssh_public_key  = tls_private_key.cluster_ssh.public_key_openssh
    repmgr_password = var.repmgr_password
    postgres_password = var.db_password
    monitor_password = var.monitor_password
  })
}
