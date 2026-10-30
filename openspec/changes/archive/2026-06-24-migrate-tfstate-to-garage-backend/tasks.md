# Tasks: Migrate Terraform State to Garage S3 Backend

Implementation plan for moving state from `terraform.tfstate` to Garage S3-compatible storage on LXC 101.

---

### Task 1: Create Garage compose.yml reference

**Type:** code
**Files:** `docker/garage/compose.yml` (CREATE)
**Depends on:** none
**Estimated effort:** small (~25 lines)

**Implementation:**
- Create `docker/garage/` directory
- Write `docker/garage/compose.yml` with:
  - Single `garage` service using pinned image (`dxflrs/garage:v1.0.1` or latest stable)
  - Container name: `garage`
  - Port mapping: `3900:3900` (S3 API), `3901:3901` (RPC internal)
  - Environment variable `GARAGE_ADMIN_TOKEN` sourced from `.env` file
  - Named volumes `garage-data` and `garage-meta` for `/var/lib/garage/data` and `/var/lib/garage/meta`
  - Config file mount: `./garage.toml:/etc/garage.toml:ro` (mounted, not created as repo file — config is deployed directly on LXC)
  - `restart: unless-stopped`
  - Follow existing patterns from `docker/deluge/compose.yml` (same service structure, network style)

**Verification:**
- `terraform fmt` passes (no Terraform files, but ensure YAML is valid)
- File follows same structure as other `docker/*/compose.yml` files

**Commit message:** `feat(garage): add compose.yml for Garage S3-compatible object storage`

---

### Task 2: Create .env.example and .gitignore entry

**Type:** config
**Files:** `docker/garage/.env.example` (CREATE), `.gitignore` (MODIFY)
**Depends on:** none
**Estimated effort:** small (~10 lines)

**Implementation:**
- Create `docker/garage/.env.example` with:
  - `GARAGE_ADMIN_TOKEN=changeme` — token for Garage admin API (used by `garage` CLI)
  - `AWS_ACCESS_KEY_ID=changeme` — S3 access key (generated post-deploy via `garage key create`)
  - `AWS_SECRET_ACCESS_KEY=changeme` — S3 secret key (generated post-deploy)
  - Follow same header/structure as `docker/lidarr/.env.example` (ASCII title, blank-line spacing)
- Create `docker/garage/.env` (LOCAL ONLY, NO COMMIT) with a generated `GARAGE_ADMIN_TOKEN` (use `openssl rand -base64 32`)
- MODIFY `.gitignore`: add `docker/garage/.env` after `docker/frigate/.env` (alphabetical by service)

**Verification:**
- `.env.example` has no real secrets
- `.gitignore` entry for `docker/garage/.env` is present

**Commit message:** `chore(garage): add .env.example and gitignore for Garage secrets`

---

### Task 3: Add S3 backend block to main.tf

**Type:** code
**Files:** `main.tf` (MODIFY)
**Depends on:** Task 2 (gitignore needed first to protect any future env leaks)
**Estimated effort:** small (~12 lines)

**Implementation:**
- Add `backend "s3"` block inside the existing `terraform {}` block, after the closing `}` of `required_providers`
- Configuration:
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
- Do NOT change any resource or provider configuration — this is a pure backend addition
- Run `terraform fmt main.tf` after edit

**Verification:**
- `terraform fmt` passes
- `terraform validate` passes (will show "backend initialization required" — expected)
- `docker/garage/.env` is in `.gitignore` (defensive cross-check)

**Commit message:** `feat(terraform): add S3 backend pointing to Garage on LXC 101`

---

### Task 4: Deploy Garage container on LXC 101 via Arcane

**Type:** infra
**Files:** (none — SSH + Arcane operations)
**Depends on:** Task 1 (compose.yml reference available)
**Estimated effort:** medium (~15 min SSH + Arcane UI)

**Implementation:**
1. SSH into LXC 101 (via Proxmox host):
   ```bash
   ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- bash"
   ```
2. Create project directory: `mkdir -p /root/docker/arcane/data/projects/garage/`
3. On the LXC, create `garage.toml` at `/root/docker/arcane/data/projects/garage/garage.toml` with content from the openspec design — includes `metadata_dir`, `data_dir`, `rpc_bind_addr`, `rpc_public_addr`, `[s3_api]` with `s3_region = "garage"` and `api_bind_addr = "[::]:3900"`, plus `[[[admin]]]` section referencing `${GARAGE_ADMIN_TOKEN}` for env var substitution
4. On the LXC, create compose.yml under the same directory — content matching `docker/garage/compose.yml` from Task 1
5. On the LXC, create `.env` with `GARAGE_ADMIN_TOKEN=<generated-value>` (same token as local `.env`)
6. In Arcane UI (http://192.168.1.142:3552):
   - Add new project "garage" pointing to `/root/docker/arcane/data/projects/garage/compose.yml`
   - Start the project
7. Verify:
   - `docker ps` shows `garage` container running
   - `curl http://192.168.1.142:3900` returns Garage status (or `--help` output)

**Verification:**
- `garage` container status: Up
- Port 3900 responds to HTTP requests

---

### Task 5: Configure Garage — bucket and API key

**Type:** infra
**Files:** `docker/garage/.env` (MODIFY — local only, add AWS keys)
**Depends on:** Task 4 (Garage must be running)
**Estimated effort:** medium (~10 min SSH + CLI)

**Implementation:**
1. SSH into LXC 101 and set up Garage CLI access:
   ```bash
   # Install garage CLI in the container
   pct exec 101 -- docker exec garage garage --help
   ```
   Or use `docker exec` directly with the container

2. Configure the single-node cluster layout:
   ```bash
   docker exec garage garage status  # verify admin connectivity
   docker exec garage garage layout assign -z dc1 -c 1 <node_id>
   docker exec garage garage layout apply --version <n>
   ```

3. Create the bucket:
   ```bash
   docker exec garage garage bucket create homelab-terraform-state
   ```

4. Create an API key for Terraform:
   ```bash
   docker exec garage garage key create terraform-operator
   ```
   Note the returned `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`

5. Allow the key to access the bucket:
   ```bash
   docker exec garage garage bucket allow homelab-terraform-state \
     --key terraform-operator \
     --permissions Read,Write,Delete
   ```

6. Update local `docker/garage/.env` with the generated AWS credentials:
   ```
   AWS_ACCESS_KEY_ID=<from key create>
   AWS_SECRET_ACCESS_KEY=<from key create>
   ```

**Verification:**
- `docker exec garage garage bucket list` shows `homelab-terraform-state`
- `docker exec garage garage key list` shows `terraform-operator`
- Export the AWS keys in terminal — ready for Terraform

---

### Task 6: Migrate local state to Garage

**Type:** infra
**Files:** (none — state migration operation)
**Depends on:** Task 3 (backend block in main.tf), Task 5 (bucket + keys ready)
**Estimated effort:** small (~5 min)

**Implementation:**
1. Export AWS credentials in terminal:
   ```bash
   export AWS_ACCESS_KEY_ID=<value>
   export AWS_SECRET_ACCESS_KEY=<value>
   ```
2. Initialize with migration:
   ```bash
   terraform init -migrate-state
   ```
3. Confirm the migration prompt: type `yes`
4. Verify:
   - Output shows "Terraform has successfully migrated the state"
   - Local `terraform.tfstate.backup` exists
   - Local `terraform.tfstate` is now a symlink or empty (S3 backend doesn't create local state)
5. List resources to verify state is intact:
   ```bash
   terraform state list
   ```

**Verification:**
- `terraform state list` returns all ~26 managed resources
- `terraform.tfstate.backup` exists locally

---

### Task 7: Verify migration end-to-end

**Type:** infra
**Files:** (none — verification)
**Depends on:** Task 6 (state migrated)
**Estimated effort:** medium (~15 min)

**Implementation:**
1. Plan verification:
   ```bash
   terraform plan
   ```
   - Output should show "No changes. Your infrastructure matches the configuration." (or expected changes if any resource is out of sync)
   - No "Inconsistent state" or "state not found" errors

2. Lock test:
   - Terminal 1: `terraform apply` (pause at prompt, don't confirm)
   - Terminal 2: `terraform plan` (should succeed, plan reads state without lock)
   - Terminal 2: `terraform apply` (should fail with lock acquisition error)
   - Confirm Terminal 1 apply, verify Terminal 2 error message

3. Container restart test:
   ```bash
   ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- docker restart garage"
   ```
   - Wait 5s, then `terraform plan` — diff should match pre-restart output

4. Unavailable test (optional):
   - `docker stop garage`
   - `terraform plan` should fail with clear backend connectivity error
   - `docker start garage`
   - `terraform plan` succeeds again

**Verification:**
- AC1: `terraform init` succeeds with S3 backend
- AC2: `terraform plan` reads from Garage, correct diff
- AC3: (implicit) Apply writes to Garage — confirmed by plan/apply cycle
- AC4: Locking prevents concurrent applies
- AC5: State survives container restart
- (AC6 documented in Task 8)

---

### Task 8: Document rollback procedure and update infra docs

**Type:** docs
**Files:** `docs/terraform-state-migration.md` (CREATE), `NETWORK.md` (MODIFY), `docker/README.md` (MODIFY)
**Depends on:** Task 6 (migration complete — rollback steps verified)
**Estimated effort:** small (~40 lines total)

**Implementation:**
1. CREATE `docs/terraform-state-migration.md` with:
   - Overview: what changed (local → Garage S3 backend)
   - Architecture: single-node Garage on LXC 101, port 3900
   - **Rollback procedure** (R5 from spec):
     1. `terraform init -migrate-state -backend=false` — reverts to local state
     2. Verify `terraform state list` shows all resources (now reading from local)
     3. Remove `backend "s3"` block from `main.tf`
     4. Stop Garage via Arcane UI (or `docker compose down`)
     5. Clean up: remove `docker/garage/` files only AFTER confirming local state works
   - References to spec and design documents in `openspec/changes/migrate-tfstate-to-garage-backend/`

2. MODIFY `NETWORK.md`:
   - Add `Garage (S3 storage)` entry to "Service Access Points" table:
     ```
     | Garage | `http://192.168.1.142:3900` | Docker (managed via Arcane) — Terraform state backend |
     ```

3. MODIFY `docker/README.md`:
   - Add Garage row to the "Running Services" table:
     ```
     | Garage | `garage` | 3900 | S3-compatible object storage (Terraform state) | Arcane |
     ```

**Verification:**
- `docs/terraform-state-migration.md` exists and describes complete rollback
- `NETWORK.md` shows Garage port 3900
- `docker/README.md` shows Garage in service table

**Commit message:** `docs: add migration and rollback documentation for Garage backend`

---

## Review Workload Forecast

| Metric | Value |
|--------|-------|
| **Estimated total changed lines** | ~86 lines |
| **Estimated files touched** | 7 files (4 CREATE, 3 MODIFY) |
| **Chained PRs recommended?** | **No** — well under chain threshold |
| **400-line budget risk** | **Low** (~21% of budget) |
| **Decision needed before apply?** | **No** — tasks are sequenced and clear |

### Files breakdown

| File | Action | Est. Lines |
|------|--------|-----------|
| `docker/garage/compose.yml` | CREATE | 25 |
| `docker/garage/.env.example` | CREATE | 10 |
| `.gitignore` | MODIFY | +1 |
| `main.tf` | MODIFY | +12 |
| `docs/terraform-state-migration.md` | CREATE | 35 |
| `NETWORK.md` | MODIFY | +1 |
| `docker/README.md` | MODIFY | +2 |
| **Total** | | **~86** |

### Execution order

```
Task 1 (compose.yml)    Task 2 (.env.example + .gitignore)
          \                  /
           \                /
            Task 3 (main.tf backend block)   Task 4 (deploy Garage)
                         \                         /
                          \                       /
                           Task 5 (bucket + keys)
                                  |
                            Task 6 (migrate state)
                                  |
                            Task 7 (verify)
                                  |
                            Task 8 (docs)
```

### Notes for executor

- Tasks 3 and 4 can run in parallel — the backend block can be committed before Garage is deployed (Terraform just won't init until Garage is reachable)
- The commit order is: Task 1, Task 2, Task 3, Task 8 (code commits), while infra tasks (4-7) run in parallel or sequence
- Recommend committing code before running infra tasks, so the PR is ready for review while infra work completes
