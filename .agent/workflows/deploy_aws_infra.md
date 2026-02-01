---
description: Deploy the AWS High Availability PostgreSQL Infrastructure
---

This workflow provisions the EC2 instances, Load Balancer, and Monitoring stack using Terraform.

1. Navigate to the terraform directory where the infrastructure code resides.
2. Initialize Terraform to download providers and modules.
3. Apply the configuration to create the resources.

// turbo
1. cd terraform
// turbo
2. terraform init
// turbo
3. AWS_PROFILE=harvest terraform apply -auto-approve
