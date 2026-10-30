# Design: Migrate Terraform State to Garage S3 Backend

## Technical Approach

Deploy a single-node Garage S3-compatible server as a Docker container (Arcane project) on LXC 101, create a dedicated bucket and API keys, then reconfigure Terraform's `backend "s3"` to point at the local Garage endpoint. Migrate existing local state via `terraform init -migrate-state`. Garage is deployed manually (SSH + Arcane) — never by Terraform — to avoid the chicken-and-egg problem.

## Architecture Decisions

### Decision: Single-node Garage (no clustering)

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Multi-node cluster | Adds complexity, 3+ nodes, consensus overhead | ✗ Rejected |
| Single-node + ZFS backup | Simpler, state fits in LXC backups (CT 101) | ✓ Selected |
| Terraform Cloud | External dependency, costs | ✗ Rejected |

**Rationale**: Single operator homelab. State durability comes from existing LXC backup regime (ZFS snapshots + `local` storage backups), not from cluster replication.

### Decision: Arcane-managed Docker deployment

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Manual `docker compose` | Works but inconsistent with existing pattern | ✗ Rejected |
| Arcane project | All services on LXC 101 follow this pattern | ✓ Selected |

**Rationale**: Every Docker service on LXC 101 is deployed via Arcane (`/root/docker/arcane/`). Garage must follow the same convention for operational consistency during recovery and backup.

### Decision: Environment variables for credentials

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Hardcoded in main.tf | Leaks to VCS | ✗ Rejected |
| Terraform Cloud env vars | Not available | ✗ Rejected |
| Local `.env` + LXC env | Gitignored, follows docker/.env.example pattern | ✓ Selected |

**Rationale**: `docker/garage/.env` holds `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Already covered by `.gitignore` (no explicit entry needed — `*.tfvars` and `docker/*/.env` patterns apply).

## Data Flow

```
Workstation                    LXC 101 (192.168.1.142)
┌──────────────────┐           ┌──────────────────────────────┐
│  terraform plan  │  HTTP     │  Docker: Garage (port 3900)  │
│  terraform apply │───────→   │  ┌────────────────────────┐  │
│  terraform init  │           │  │ Bucket:                │  │
│                  │  S3 API   │  │ homelab-terraform-state│  │
│  env vars:       │           │  │ Key: terraform.tfstate │  │
│  AWS_ACCESS_KEY  │           │  └────────────────────────┘  │
│  AWS_SECRET_KEY  │           │  Data: /var/lib/garage/      │
└──────────────────┘           └──────────────────────────────┘
                                       │
                                       │ LXC backup includes
                                       ▼
                               Proxmox Backup (local storage)
```

State never leaves the LAN. All S3 operations go through `http://192.168.1.142:3900`.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `docker/garage/compose.yml` | Create | Garage service with pinned image, volumes, ports |
| `docker/garage/.env` | Create | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `GARAGE_ADMIN_TOKEN` |
| `docker/garage/.env.example` | Create | Template without secrets |
| `main.tf` | Modify | Add `backend "s3"` block inside `terraform {}` |
| `.gitignore` | Modify | Add `docker/garage/.env` (defensive — verify existing patterns) |

No new Terraform-managed resources. No change to any `.tf` resource file.

## Garage Configuration

Garage config (`/root/docker/arcane/data/projects/garage/garage.toml`) on LXC 101:

```toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "192.168.1.142:3901"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage"
```

Post-deployment CLI steps (SSH into LXC 101):
1. `garage bucket create homelab-terraform-state`
2. `garage key create terraform-operator`
3. `garage bucket allow homelab-terraform-state --key terraform-operator --permissions Read,Write,Delete`

## Backend Configuration

```hcl
terraform {
  # ... existing required_providers block ...

  backend "s3" {
    bucket                      = "homelab-terraform-state"
    key                         = "terraform.tfstate"
    region                      = "garage"
    endpoints = {
      s3 = "http://192.168.1.142:3900"
    }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
```

## State Locking

Garage supports conditional PUT (etag-based) which Terraform's S3 backend uses for state locking. Over plain HTTP (no HTTPS), locking reliability depends on Garage's internal consistency — adequate for single-operator use. No DynamoDB fallback available; acceptable risk.

## Migration / Rollout

1. Deploy Garage via SSH: `scp docker/garage/compose.yml root@192.168.1.142:/root/docker/arcane/data/projects/garage/` then apply via Arcane UI
2. SSH into LXC 101, create bucket and key pair via `garage` CLI
3. Write `docker/garage/.env` locally with credentials (gitignored)
4. Add `backend "s3"` block to `main.tf`
5. Run `terraform init -migrate-state` — copies `terraform.tfstate` to Garage
6. Verify: `terraform state list`, `terraform plan` produce correct output
7. Commit `main.tf`, `docker/garage/compose.yml`, `docker/garage/.env.example`

## Rollback Plan

- `terraform init -migrate-state -backend=false` reverts to local state
- `terraform.tfstate.backup` retained on local filesystem as safety net
- `docker compose -f docker/garage/compose.yml down` via SSH or Arcane
- Remove `backend "s3"` block from `main.tf`

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| LXC 101 down → plan/apply fails | Medium | Local `*.backup` retained |
| Garage version drift breaks S3 API | Low | Pin image tag to `v1.0.1` |
| State locking unreliable over HTTP | Low | Single operator; no concurrent applies |
| Credential leak | Low | `.env` gitignored, never committed |

## Open Questions

- Verify Garage S3 compat handles `skip_s3_checksum = true` correctly
- Confirm Garage image tag supports arm64 (N100 is x86_64, but verify)
