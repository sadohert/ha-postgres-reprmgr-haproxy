# --- Outputs ---

# 1. SSH Access
output "ssh_access" {
  description = "SSH Connection Strings for all nodes"
  value = merge(
    {
      "pg1 [Primary]" = "ssh -i ${var.ssh_key_name}.pem ubuntu@${aws_instance.primary.public_ip}"
    },
    {
      for i, instance in aws_instance.standbys :
      "pg${i + 2} [Standby]" => "ssh -i ${var.ssh_key_name}.pem ubuntu@${instance.public_ip}"
    },
    {
      "monitor" = "ssh -i ${var.ssh_key_name}.pem ubuntu@${aws_instance.monitor.public_ip}"
    }
  )
}

# 2. Database Endpoints
output "database_endpoints" {
  description = "Connection strings for Postgres (Admin/Write and Read)"
  value = {
    "primary_write" = nonsensitive("postgres://mmuser:${var.mm_password}@${aws_lb.ha_postgres.dns_name}:5000/mattermost")
    "read_replicas" = nonsensitive("postgres://mmuser:${var.mm_password}@${aws_lb.ha_postgres.dns_name}:5001/mattermost")
  }
  sensitive = false
}

# 3. Metrics Endpoints
output "metrics_endpoints" {
  description = "Monitoring URLs"
  value = {
    "grafana"    = "http://${aws_instance.monitor.public_ip}:3000"
    "prometheus" = "http://${aws_instance.monitor.public_ip}:9090"
  }
}

output "grafana_admin_password" {
  description = "Admin password for Grafana"
  value       = nonsensitive(random_password.grafana_admin_password.result)
}

# 4. App Configuration
output "app_configuration" {
  description = "Configuration for Applications (Mattermost)"
  value = {
    "mattermost_db" = nonsensitive("postgres://mmuser:${var.mm_password}@${aws_lb.ha_postgres.dns_name}:5000/mattermost")
  }
  sensitive = false
}

# 5. DC2 SSH Access
output "dc2_ssh_access" {
  description = "SSH access for DC2 nodes (only when dc2_enabled = true)"
  value = var.dc2_enabled ? merge(
    { "pg4 [DC2 Upstream]" = "ssh -i ${var.ssh_key_name}.pem ubuntu@${aws_instance.dc2_upstream[0].public_ip}" },
    { for i, inst in aws_instance.dc2_standbys :
      "pg${i + 5} [DC2 Standby]" => "ssh -i ${var.ssh_key_name}.pem ubuntu@${inst.public_ip}" }
  ) : {}
}

# 6. DC2 Database Endpoints
output "dc2_database_endpoints" {
  description = "Connection strings for DC2 Postgres via DC2 NLB (only when dc2_enabled = true)"
  value = var.dc2_enabled ? {
    "write" = nonsensitive("postgres://mmuser:${var.mm_password}@${aws_lb.ha_postgres_dc2[0].dns_name}:5000/mattermost")
    "read"  = nonsensitive("postgres://mmuser:${var.mm_password}@${aws_lb.ha_postgres_dc2[0].dns_name}:5001/mattermost")
  } : {}
  sensitive = false
}
