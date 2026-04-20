# --- Dedicated EBS Volumes for Postgres Data ---


# Data source to get subnet details (specifically AZ) from the filtered list (local.selected_subnets)
# We need to map the subnet ID back to an AZ. We can use data.aws_subnet again or just rely on the fact 
# that we picked them. But aws_ebs_volume needs AZ.
# Easiest is to lookup each selected subnet.

data "aws_subnet" "selected_primary" {
  id = local.selected_subnets[0]
}

resource "aws_ebs_volume" "primary_data" {
  availability_zone = data.aws_subnet.selected_primary.availability_zone
  size              = 50
  type              = "gp3"

  tags = {
    Name = "pg1-data"
  }
}

resource "aws_volume_attachment" "primary_data_attach" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.primary_data.id
  instance_id = aws_instance.primary.id
}

data "aws_subnet" "selected_standby" {
  count = 2
  id    = local.selected_subnets[count.index + 1]
}

resource "aws_ebs_volume" "standby_data" {
  count             = 2
  availability_zone = data.aws_subnet.selected_standby[count.index].availability_zone
  size              = 50
  type              = "gp3"

  tags = {
    Name = "pg${count.index + 2}-data"
  }
}

resource "aws_volume_attachment" "standby_data_attach" {
  count       = 2
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.standby_data[count.index].id
  instance_id = aws_instance.standbys[count.index].id
}

# --- DC2 EBS Data Volumes ---

resource "aws_ebs_volume" "dc2_upstream_data" {
  count             = var.dc2_enabled ? 1 : 0
  availability_zone = data.aws_subnet.selected_primary.availability_zone
  size              = 50
  type              = "gp3"

  tags = {
    Name = "pg4-data"
  }
}

resource "aws_volume_attachment" "dc2_upstream_data_attach" {
  count       = var.dc2_enabled ? 1 : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.dc2_upstream_data[0].id
  instance_id = aws_instance.dc2_upstream[0].id
}

resource "aws_ebs_volume" "dc2_standby_data" {
  count             = var.dc2_enabled ? 2 : 0
  availability_zone = data.aws_subnet.selected_standby[count.index].availability_zone
  size              = 50
  type              = "gp3"

  tags = {
    Name = "pg${count.index + 5}-data"
  }
}

resource "aws_volume_attachment" "dc2_standby_data_attach" {
  count       = var.dc2_enabled ? 2 : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.dc2_standby_data[count.index].id
  instance_id = aws_instance.dc2_standbys[count.index].id
}
