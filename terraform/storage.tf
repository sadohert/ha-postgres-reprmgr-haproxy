# --- Dedicated EBS Volumes for Postgres Data ---


# Data source to get subnet details (specifically AZ) from the filtered list in main.tf
data "aws_subnet" "selected" {
  count = 3
  id    = data.aws_subnets.default.ids[count.index]
}

resource "aws_ebs_volume" "pg_data" {
  count             = 3
  availability_zone = data.aws_subnet.selected[count.index].availability_zone
  size              = 50 # 50GB as per guide requirements
  type              = "gp3"

  tags = {
    Name = "pg${count.index + 1}-data"
  }
}

resource "aws_volume_attachment" "pg_data_attach" {
  count       = 3
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.pg_data[count.index].id
  instance_id = aws_instance.db_nodes[count.index].id
}
