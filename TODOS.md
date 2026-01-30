# Setup & Documentation
* Ensure Mattermost Postgres best practices from HA documentation are reflected in the postgres.conf changes required.  I think the current docs don't have all the settings.
* THink about the connection settings.  Does HAProxy's configuration we're documenting need to account for what we're telling the customer for Mattermost `SqlSettings` (in terms of MaxConns, MaxOpenConns, timeouts, etc.)
* Should PGBouncer play a role here?
* Need to test this setup line "> **Note**: For production, replace `trust` with `scram-sha-256` and configure `.pgpass` files."  I don't know what a .pgpass is.

# Optimizations
* VIP Follows Primary - Make Keepalived track PostgreSQL primary role so VIP moves to the DB primary node
  * Reduces inter-node latency (important for realtime workloads with no cluster affinity)
  * Implementation: Add `check_primary.sh` script using `/master` endpoint with high weight in Keepalived
  * Trade-off: VIP moves on every DB failover (not just node failures)
* Loki for log aggregation

# Future Work: Infrastructure & Scale
* **AWS HA Postgres Design (Terraform)**:
  * Port this local `multipass` HA design to AWS.
  * Document variances from the reference design.
  * Use Terraform for provisioning.
* **Load Testing at Scale**:
  * Run Mattermost load tests against the AWS environment.
  * Validate performance at higher scale.

# Validation
* Load Test
 * Setup Mattermost server to point to multipass cluster
 * Setup mattermost-loadtest-ng project to generate load and monitor
 * Test failure conditions