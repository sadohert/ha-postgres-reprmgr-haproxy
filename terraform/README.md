# AWS HA Postgres Deployment

This Terraform module deploys a 3-node HA Postgres cluster that mimics our local Multipass reference design, adapted for AWS best practices.

## Architecture

*   **VPC**: Deploy into the **AWS Default VPC** for simplicity.
*   **Compute**: 3x `t3.medium` EC2 instances running Ubuntu 24.04 LTS.
    *   **Public Access**: Instances are assigned Public IPs for easy SSH access (Security Groups restricts this to Admin IP).
*   **Storage**:
    *   Root Volume: 20GB gp3.
    *   Data Volume: 50GB gp3 dedicated EBS attached to `/dev/sdf`.
*   **Networking (The Major Variance)**:
    *   **No Floating VIP**: AWS does not support Gratuitous ARP for VIPs.
    *   **Solution**: **Network Load Balancer (NLB)** (Internal Scheme).
        *   **Port 5000 (Write)**: Routes traffic *only* to the Primary node (Health check passes only on Primary).
        *   **Port 5001 (Read)**: Routes traffic to Standby nodes (Health check passes on Replicas).
        *   **Health Check**: Uses the same `pgchk.py` script from the reference design running on port 8008.

## Usage

1.  **Configure Variables**:
    Create a `terraform.tfvars` file or use defaults:
    ```hcl
    aws_region   = "us-east-1"
    ssh_key_name = "my-key-pair"     # Must exist in AWS
    admin_cidr   = "203.0.113.5/32"  # Your IP for SSH access
    ```

2.  **Deploy**:
    ```bash
    terraform init
    terraform apply
    ```

3.  **Post-Provisioning Setup**:
    After the instances are up, follow the **Setup Guide** (`docs/02-setup-guide.md`) beginning at **Phase 1**.
    
    *   **Important**: Skip **Phase 6 (Keepalived)** entirely. The NLB handles routing.
    *   **EBS Volume**: You must mount the dedicated volume on first boot:
        ```bash
        # On each node
        sudo mkfs.xfs /dev/nvme1n1
        sudo mount /dev/nvme1n1 /var/lib/postgresql
        ```

## Outputs

After deployment, Terraform will output:
*   `nlb_dns_name`: Use this as your Application Host.
*   `connection_string_write`: Primary DB Connection string.
*   `connection_string_read`: Replica DB Connection string.
*   `db_node_ips`: Private IPs to SSH into (via Bastion).
