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

# EC2 Describe and Tags policies removed (Static discovery implemented)

resource "aws_iam_role_policy_attachment" "ec2_read" {
  role       = aws_iam_role.db_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.db_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "db_profile" {
  name = "ha-postgres-profile"
  role = aws_iam_role.db_role.name
}
