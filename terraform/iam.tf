# --- IAM Role for EC2 Peer Discovery ---

resource "aws_iam_role" "db_role" {
  name = "ha-postgres-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "db_policy" {
  name = "ha-postgres-policy"
  role = aws_iam_role.db_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "db_profile" {
  name = "ha-postgres-profile"
  role = aws_iam_role.db_role.name
}
