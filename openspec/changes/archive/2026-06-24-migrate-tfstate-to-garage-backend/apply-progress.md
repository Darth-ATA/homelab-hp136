# Apply Progress: Migrate Terraform State to Garage S3 Backend

**What**: Fixed CRITICAL and WARNING findings from verify report for migrate-tfstate-to-garage-backend change

**Why**: Verify phase found 2 CRITICAL and 2 WARNING issues that needed fixing before deployment

**Where**: 
- docker/garage/garage.toml (new) — minimal single-node config with env var references
- docker/garage/compose.yml — added config file mount, exposed all ports, kept required env vars
- scripts/deploy-garage.sh — fixed header, added garage.toml copy step and pre-flight check
- NETWORK.md — added Garage to service access points (4 ports)
- docker/README.md — added Garage to services table, URLs, and Arcane project listing
- main.tf — terraform fmt (equals-sign padding removed)
- docs/terraform-state-migration.md — clarified S3 etag-based locking (not DynamoDB advisory locking)

**Learned**: Garage's config file supports `${VAR}` env var expansion at runtime, so admin/metrics tokens must remain in compose.yml environment section even though they're also referenced in garage.toml. The verify report suggestion #6 was partially incorrect — these env vars ARE needed for config file resolution, not as direct binary flags.
