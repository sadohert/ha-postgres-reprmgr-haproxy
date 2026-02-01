output "vpc_id" {
  description = "VPC ID"
  value       = data.aws_vpc.default.id
}

output "db_node_public_ips" {
  description = "Public IPs of the Database Nodes"
  value       = {
    pg1 = aws_instance.db_nodes[0].public_ip
    pg2 = aws_instance.db_nodes[1].public_ip
    pg3 = aws_instance.db_nodes[2].public_ip
  }
}

output "nlb_dns_name" {
  description = "DNS Name of the Internal Network Load Balancer"
  value       = aws_lb.ha_postgres.dns_name
}

output "connection_string_write" {
  description = "PostgreSQL Connection String for Writes (Primary)"
  value       = "postgres://postgres:${var.db_password}@${aws_lb.ha_postgres.dns_name}:5000/postgres"
  sensitive   = true
}

output "connection_string_read" {
  description = "PostgreSQL Connection String for Reads (Replicas)"
  value       = "postgres://postgres:${var.db_password}@${aws_lb.ha_postgres.dns_name}:5001/postgres"
  sensitive   = true
}
