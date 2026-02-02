# AWS SSM Operations Guide: HA PostgreSQL

This guide provides common commands for managing the HA PostgreSQL cluster using AWS Systems Manager (SSM) Run Command. These commands allow you to perform maintenance and troubleshooting without needing direct SSH access.

## Prerequisites

- Instances must have the AmazonSSMManagedInstanceCore IAM policy attached (included in the Terraform deployment).
- AWS CLI configured with appropriate permissions.

## 📋 Common SSM Commands

### Check Service Status
Verify that all key services are running on a node.
```bash
aws ssm send-command \
    --instance-ids "INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl status postgresql", "sudo systemctl status repmgrd", "sudo systemctl status haproxy", "sudo systemctl status pgchk"]' \
    --region us-east-1
```

### View repmgr Cluster Status
Check the role and status of all nodes from any node in the cluster.
```bash
aws ssm send-command \
    --instance-ids "INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo -u postgres repmgr -f /etc/repmgr.conf cluster show"]' \
    --region us-east-1
```

### Troubleshoot Provisioning (user-data)
If a node feels "empty" (missing services/users), check the user-data logs.
```bash
aws ssm send-command \
    --instance-ids "INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["ls -l /var/log/user-data.log", "tail -n 50 /var/log/user-data.log"]' \
    --region us-east-1
```

### Monitor Postgres Logs
View the last few lines of the PostgreSQL log.
```bash
aws ssm send-command \
    --instance-ids "INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo tail -n 50 /var/log/postgresql/postgresql-17-main.log"]' \
    --region us-east-1
```

## 🛠️ Retrieving Command Output
After sending a command, retrieve the execution details using the `CommandId`:
```bash
aws ssm get-command-invocation \
    --command-id "COMMAND_ID" \
    --instance-id "INSTANCE_ID" \
    --region us-east-1
```
