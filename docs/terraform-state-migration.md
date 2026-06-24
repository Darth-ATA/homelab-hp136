# Terraform State Migration to Garage S3 Backend

Migrate Terraform state from local `terraform.tfstate` to [Garage](https://garagehq.deuxfleurs.fr/) S3-compatible object storage running on LXC 101.

## Architecture

```
Workstation (terraform)
  │  S3 API (HTTP)
  ▼
LXC 101 (192.168.1.142:3900)
  │  Garage Docker container
  ▼
/var/lib/garage/ (named volume → ZFS backup)
```

- **Bucket:** `homelab-terraform-state`
- **State key:** `terraform.tfstate`
- **Region:** `garage`
- **Endpoint:** `http://192.168.1.142:3900`

## Prerequisites

1. **Garage deployed and running** on LXC 101 — see [Deploy Garage](#deploy-garage)
2. **Bucket and API keys created** — see [Setup Bucket](#setup-bucket-and-keys)
3. **Local `.env` populated** — copy `docker/garage/.env.example` → `docker/garage/.env` with credentials
4. **Terraform v1.6+** (S3 native backend support, no extra plugin)

## Deploy Garage

Run the deploy script:

```bash
# 1. Populate .env with admin tokens first
cp docker/garage/.env.example docker/garage/.env
# Edit docker/garage/.env — generate tokens:
#   openssl rand -hex 32

# 2. Deploy to LXC 101
./scripts/deploy-garage.sh
```

The script will:

1. SSH into LXC 101 and create the Arcane project directory
2. Copy `docker/garage/compose.yml` to the LXC
3. Copy `docker/garage/.env` to the LXC
4. Pre-pull the Garage Docker image
5. Provide instructions to complete setup via the Arcane UI

### Manual Verification

```bash
# Check Garage is running
ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- docker ps --filter name=garage"

# Check S3 endpoint responds
ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- curl -s -o /dev/null -w '%{http_code}' http://localhost:3900/"
```

## Setup Bucket and Keys

Run the setup script to create the bucket and API key:

```bash
./scripts/setup-garage-state.sh
```

This script will:

1. Verify Garage container is running
2. Create bucket `homelab-terraform-state`
3. Create API key `terraform-operator` with read/write/delete on the bucket
4. Update `docker/garage/.env` locally with the credentials
5. Update the remote `.env` on LXC 101
6. Output export commands for immediate use

### Manual Alternative

If you prefer to do it manually or need to troubleshoot:

```bash
# SSH into LXC 101
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct enter 101"

# Inside LXC 101, run garage CLI commands
docker exec garage garage bucket create homelab-terraform-state
docker exec garage garage key create terraform-operator
docker exec garage garage bucket allow homelab-terraform-state \
  --key terraform-operator --read --write --delete
docker exec garage garage key info terraform-operator
```

Save the **Access Key ID** and **Secret Key** from the output.

## Migrate State

### Step 1: Export credentials

```bash
# Source from .env
set -a
source docker/garage/.env
set +a

# Or export manually
export AWS_ACCESS_KEY_ID="<from setup script output>"
export AWS_SECRET_ACCESS_KEY="<from setup script output>"
```

### Step 2: Migrate

```bash
terraform init -migrate-state
```

Terraform will:

- Detect the new S3 backend configuration in `main.tf`
- Copy the local state file to Garage
- Create a backup at `terraform.tfstate.backup`

Type `yes` when prompted to copy existing state.

### Step 3: Verify migration

```bash
# List managed resources from remote state
terraform state list

# Run a plan (should show no changes)
terraform plan
```

Both commands should succeed and show the same resources as before.

## Verification Checklist

| # | Test | Expected Result | Status |
|---|------|----------------|--------|
| 1 | `terraform init` | Updates backend, no migration prompt (already migrated) | |
| 2 | `terraform state list` | Shows all ~26 managed resources | |
| 3 | `terraform plan` | No changes (infrastructure unchanged) | |
| 4 | Lock test: run two `terraform apply` simultaneously | Second one fails with lock error | |
| 5 | `docker restart garage` then `terraform plan` | Works, state intact | |
| 6 | Stop Garage, then `terraform plan` | Clear error about endpoint unreachable | |

## Rollback

If migration fails or you need to revert to local state:

```bash
# 1. Restore state from backup (if available)
cp terraform.tfstate.backup terraform.tfstate

# 2. Migrate back to local backend
terraform init -migrate-state -backend=false

# 3. Remove the backend block from main.tf
# Edit main.tf and delete the backend "s3" { ... } block

# 4. Verify local state works
terraform plan
```

To completely decommission Garage:

```bash
# Stop Garage via Arcane UI or CLI
# Delete bucket (optional, keeps data)
docker exec garage garage bucket delete homelab-terraform-state

# Remove Arcane project
rm -rf /root/docker/arcane/data/projects/garage/
```

## Troubleshooting

### Garage container not running

```bash
# Check logs
ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- docker logs garage"

# Verify .env exists on LXC
ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- ls -la /root/docker/arcane/data/projects/garage/"
```

### Terraform init fails with "failed to configure the backend"

- Ensure `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are exported in your shell
- Verify Garage is running: `docker ps` on LXC 101
- Check port 3900 is accessible from your workstation

### State lock issues

```bash
# Force unlock (only if you're sure no apply is running)
terraform force-unlock <lock-id>
```

### "Bucket does not exist" error

Re-run the setup script or create manually:

```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- docker exec garage garage bucket create homelab-terraform-state"
```

### Credential errors

- Verify `docker/garage/.env` has valid keys
- Source the file before running terraform: `source docker/garage/.env`
- Confirm the key has permissions: `docker exec garage garage bucket allow ...`

## Service Reference

| Property | Value |
|----------|-------|
| Service | Garage S3-compatible storage |
| Container | `garage` |
| LXC | 101 (docker, 192.168.1.142) |
| Port | 3900 (S3 API) |
| Image | `dxflrs/garage:v1.0.1` |
| Arcane project | `/root/docker/arcane/data/projects/garage/` |
| Reference compose | `docker/garage/compose.yml` |
| .env (local) | `docker/garage/.env` (gitignored) |
| Data volume | `garage-data:/var/lib/garage` |
| Bucket | `homelab-terraform-state` |
| State key | `terraform.tfstate` |
| API key | `terraform-operator` |
