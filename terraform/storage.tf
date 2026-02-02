# --- Dedicated EBS Volumes for Postgres Data ---


# Data source to get subnet details (specifically AZ) from the filtered list in main.tf
data "aws_subnet" "selected" {
  count = 3
  id    = data.aws_subnets.default.ids[count.index]
}

resource "aws_ebs_volume" "primary_data" {
  availability_zone = data.aws_subnet.selected[0].availability_zone
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

resource "aws_ebs_volume" "standby_data" {
  count             = 2
  availability_zone = data.aws_subnet.selected[count.index + 1].availability_zone
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
