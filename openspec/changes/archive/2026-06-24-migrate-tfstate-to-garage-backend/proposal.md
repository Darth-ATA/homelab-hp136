# Proposal: Migrate Terraform State to Garage S3 Backend

## Intent

Eliminate risk of local state loss. Currently ~26 resources managed via Terraform with 100% local state in `terraform.tfstate`. No remote backend means state is unrecoverable if workstation fails. Garage provides S3-compatible object storage self-hosted on the homelab, keeping state inside the network.

## Scope

### In Scope
- Deploy Garage as Docker container on LXC 101 (`docker/garage/compose.yml`)
- Configure `backend "s3"` in `main.tf` pointing to Garage at `http://192.168.1.142:3900`
- Apply `terraform init -migrate` to copy existing state to Garage
- Garage data persisted in `/var/lib/garage/` on LXC 101 (outside ZFS dataset, included in LXC backups)
- Environment variables for access/secret keys (via `.env` or LXC env)

### Out of Scope
- Multi-region or multi-node Garage cluster
- Garage monitoring, alerting, or dashboard
- Performance tuning or benchmarking
- Terraform Cloud or other managed backends

## Capabilities

> No spec-level changes — this is a pure infrastructure/config change. Requirements remain identical; only the state storage mechanism changes.

### New Capabilities
None

### Modified Capabilities
None

## Approach

| Step | What | Where |
|------|------|-------|
| 1 | Deploy Garage container with compose.yml | `docker/garage/compose.yml` |
| 2 | Create Garage bucket `homelab-terraform-state` | Via Garage admin CLI on LXC 101 |
| 3 | Generate S3 access/secret key pair | Garage admin CLI |
| 4 | Add `backend "s3"` block to terraform block | `main.tf` |
| 5 | Set env vars `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | `.env` or LXC env |
| 6 | Run `terraform init -migrate` | Local workstation |
| 7 | Keep `terraform.tfstate.backup` as safety net | Local filesystem |

Key config for `main.tf`:
```hcl
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
```

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `main.tf` | Modified | Add `backend "s3"` block |
| `docker/garage/compose.yml` | New | Garage service definition |
| `.env` or LXC 101 env | Modified | Add AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| State inaccessible if LXC 101 is down | Medium | Local `.backup` file retained; `terraform_remote_state` data sources only used at plan/apply time |
| State loss if LXC 101 destroyed | Low | `/var/lib/garage/` included in ZFS snapshot backups |
| State locking may fail over HTTP | Low | Can fall back to `use_lockfile = true` or skip locking |
| Garage version drift breaks S3 API | Low | Pin image tag in compose.yml |
| Chicken-and-egg: Terraform manages the host | Low | Deploy Garage via SSH + manual compose, not via Terraform |

## Rollback Plan

1. `terraform init -migrate-state -backend=false` to revert to local state
2. Restore from `terraform.tfstate.backup` if needed
3. `docker compose -f docker/garage/compose.yml down` to remove Garage
4. Remove `backend "s3"` block from `main.tf`
5. Delete Garage bucket and keys

## Dependencies

- Docker engine running on LXC 101 (192.168.1.142)
- SSH access to LXC 101 for initial Garage setup
- Port 3900 open on LXC 101 firewall

## Success Criteria

- [ ] `terraform init` succeeds with remote state
- [ ] `terraform plan` reads state from Garage and produces correct diff
- [ ] `terraform apply` writes updated state back to Garage
- [ ] State locking works (prevent concurrent `apply`)
- [ ] `terraform state list` shows all ~26 resources
- [ ] State survives LXC 101 container restart
