# Terraform State Backend with Garage

## Purpose

Migrate Terraform state from local `terraform.tfstate` to Garage S3-compatible object storage running on LXC 101, eliminating the single-point-of-failure of workstation-local state for ~26 managed resources.

## Requirements

### R1: State Persistence

Backend MUST store Terraform state in Garage via S3-compatible API, using environment-variable credentials.

| Attribute | Value |
|-----------|-------|
| Bucket | `homelab-terraform-state` |
| Key | `terraform.tfstate` |
| Endpoint | `http://192.168.1.142:3900` |

#### Scenario: Initial migration
- GIVEN local `terraform.tfstate` exists with all managed resources
- WHEN user runs `terraform init -migrate-state`
- THEN state is copied to Garage bucket
- AND `terraform.tfstate.backup` is created locally as safety net

#### Scenario: Normal plan/apply
- GIVEN remote state in Garage
- WHEN user runs `terraform plan` or `terraform apply`
- THEN Terraform reads state from Garage endpoint
- AND writes updated state back after apply

### R2: State Locking (RACE prevention)

Terraform MUST lock state during apply to prevent concurrent modifications.

#### Scenario: Lock contention
- GIVEN `terraform apply` holds a lock
- WHEN a second `terraform apply` starts concurrently
- THEN the second apply MUST fail with lock acquisition error
- AND the first apply MUST complete normally

### R3: Resilience

State MUST survive container lifecycle events.

#### Scenario: Container restart persistence
- GIVEN state stored in Garage
- WHEN LXC 101 Garage container is restarted
- THEN state MUST remain intact and readable after restart
- AND `terraform plan` MUST produce identical diff pre/post restart

#### Scenario: Garage unavailable
- GIVEN Garage container is stopped
- WHEN user runs `terraform plan`
- THEN Terraform MUST fail with a clear backend connectivity error
- AND user MAY restore from local `terraform.tfstate.backup`

### R4: Credential Security

Credentials MUST NOT appear in Terraform code or version control.

#### Scenario: Env-only credentials
- GIVEN Garage access/secret keys exist
- WHEN Terraform initializes or runs
- THEN credentials MUST be read from env vars only (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- AND MUST NOT be in any `.tf` file, `.tfvars`, or committed file

### R5: Rollback

Migration MUST be fully reversible with documented steps.

#### Scenario: Revert to local state
- GIVEN remote state in Garage exists
- WHEN user runs `terraform init -migrate-state -backend=false`
- THEN state is copied back to local `terraform.tfstate`
- AND backend block can be removed from `main.tf`
- AND Garage can be decommissioned without data loss

## Acceptance Criteria

| ID | Criterion | Verification |
|----|-----------|-------------|
| AC1 | `terraform init` succeeds with S3 backend | Run `terraform init` — no errors |
| AC2 | Plan reads state from Garage | Run `terraform plan` — correct diff, no "no state" warning |
| AC3 | Apply writes state to Garage | Run `terraform apply` — verify bucket content via Garage API |
| AC4 | State locking works | Start two concurrent applies — second fails |
| AC5 | State survives container restart | `docker restart garage` — plan produces same diff |
| AC6 | Rollback is documented and verified | Follow rollback steps — local state is functional again |

## Notes on Scope

All requirements are **NEW** (no existing specs to modify). This is a pure infrastructure change — Terraform resource configuration remains unchanged; only state storage location changes.
