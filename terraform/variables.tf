variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}



variable "instance_type" {
  description = "EC2 Instance Type for DB Nodes"
  type        = string
  default     = "t3.medium"
}

variable "ssh_key_name" {
  description = "Name of the SSH Key Pair to use for instances"
  type        = string
  default     = "ha-postgres-admin-key"
}

variable "admin_cidr" {
  description = "CIDR block allowed to SSH into instances (e.g., your IP)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_password" {
  description = "Password for the 'postgres' superuser"
  type        = string
  default     = "Sausage-Bacon-123!" # Odd, static, and delicious
  sensitive   = true
}

variable "repmgr_password" {
  description = "Password for the 'repmgr' replication user"
  type        = string
  default     = "Replication-Rocks-2024!"
  sensitive   = true
}

variable "monitor_password" {
  description = "Password for the 'postgres_exporter' user"
  type        = string
  default     = "Eye-Of-Sauron-See-All!"
  sensitive   = true
}
