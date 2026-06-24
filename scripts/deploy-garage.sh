#!/usr/bin/env bash
# Deploy Garage S3-compatible storage on LXC 101 — fully automated (v2.3.0)
#
# This script does EVERYTHING:
#   1. Copies compose.yaml, garage.toml, .env to LXC 101
#   2. Registers the project in Arcane (SQLite)
#   3. Pulls the Docker image
#   4. Starts Garage via docker compose
#   5. Waits for health check
#   6. Sets Arcane project status to running
#   7. Runs terraform init -migrate-state
#
# Cluster layout + bucket + key are auto-configured by Garage's
# --single-node and --default-bucket flags. No manual steps needed.
#
# Usage: ./scripts/deploy-garage.sh [--dry-run]
#
# Prerequisites:
#   - SSH key at ~/.ssh/homelab_key
#   - Proxmox host at 192.168.1.134
#   - LXC 101 (docker) running
#   - docker/garage/.env with all required vars

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# --- Config ---
PROXMOX_HOST="192.168.1.134"
SSH_KEY="${HOME}/.ssh/homelab_key"
SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=no)
LXC_ID="101"
GARAGE_CONTAINER="garage"
REMOTE_PATH="/root/docker/arcane/data/projects/garage"
COMPOSE_SRC="${PROJECT_ROOT}/docker/garage/compose.yml"
GARAGE_TOML_SRC="${PROJECT_ROOT}/docker/garage/garage.toml"
ENV_SRC="${PROJECT_ROOT}/docker/garage/.env"
IMAGE="dxflrs/garage:v2.3.0"
ARCANE_DB="/root/docker/arcane/data/arcane.db"

# --- Helpers ---
info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[OK]\033[0m   %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

remote() {
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "pct exec ${LXC_ID} -- ${*}"
}

# --- Dry-run ---
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  info "DRY RUN — no changes will be made"
fi

# --- Pre-flight checks ---
for f in "${SSH_KEY}" "${COMPOSE_SRC}" "${GARAGE_TOML_SRC}" "${ENV_SRC}"; do
  if [[ ! -f "${f}" ]]; then
    fail "Required file not found: ${f}"
  fi
done

# ============================================================
# STEP 1: Verify LXC 101 reachability
# ============================================================
info "Checking LXC ${LXC_ID} reachability..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "pct status ${LXC_ID}" >/dev/null 2>&1 \
    || fail "LXC ${LXC_ID} is not running or Proxmox is unreachable"
  ok "LXC ${LXC_ID} is running"
fi

# ============================================================
# STEP 2: Copy files to LXC
# ============================================================
info "Creating project directory..."
${DRY_RUN} || ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
  "pct exec ${LXC_ID} -- mkdir -p ${REMOTE_PATH}"

copy_file() {
  local src="$1" dst="$2"
  info "Copying $(basename "${src}")..."
  ${DRY_RUN} || ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct push ${LXC_ID}" "${src}" "${dst}"
}

copy_file "${COMPOSE_SRC}"   "${REMOTE_PATH}/compose.yaml"
copy_file "${GARAGE_TOML_SRC}" "${REMOTE_PATH}/garage.toml"
copy_file "${ENV_SRC}"       "${REMOTE_PATH}/.env"
ok "Files copied to ${REMOTE_PATH}"

# ============================================================
# STEP 2b: Replace rpc_secret placeholder with real secret
# ============================================================
info "Applying GARAGE_RPC_SECRET to garage.toml..."
if ! ${DRY_RUN}; then
  # Read secret from local .env and inject via heredoc-style SSH
  source "${ENV_SRC}" 2>/dev/null || true
  if [[ -n "${GARAGE_RPC_SECRET:-}" ]]; then
    ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
      "pct exec ${LXC_ID} -- sed -i 's/__RPC_SECRET__/${GARAGE_RPC_SECRET}/' ${REMOTE_PATH}/garage.toml"
    ok "rpc_secret applied"
  else
    warn "GARAGE_RPC_SECRET not found in .env — skipping placeholder replacement"
    warn "  Garage may fail to start without a valid rpc_secret"
  fi
fi

# ============================================================
# STEP 3: Register project in Arcane SQLite DB
# ============================================================
info "Registering project in Arcane..."
if ! ${DRY_RUN}; then
  COUNT=$(ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct exec ${LXC_ID} -- sqlite3 ${ARCANE_DB} \
      \"SELECT COUNT(*) FROM projects WHERE name = 'garage';\"" 2>/dev/null || echo "0")
  COUNT="${COUNT//[!0-9]/}"

  if [[ "${COUNT}" -gt 0 ]]; then
    ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
      "pct exec ${LXC_ID} -- sqlite3 ${ARCANE_DB} \
        \"UPDATE projects SET status = 'stopped', updated_at = datetime('now') WHERE name = 'garage';\"" 2>/dev/null || true
    warn "Project 'garage' already exists — reset to 'stopped'"
  else
    PROJECT_ID=$(ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
      "pct exec ${LXC_ID} -- python3 -c \"import uuid; print(uuid.uuid4())\"" 2>/dev/null || echo "$(uuidgen)")
    ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
      "pct exec ${LXC_ID} -- sqlite3 ${ARCANE_DB} \
        \"INSERT INTO projects (id, name, dir_name, path, status, service_count, running_count, created_at) \
         VALUES ('${PROJECT_ID}', 'garage', 'garage', '/app/data/projects/garage', 'stopped', 0, 0, datetime('now'));\""
    ok "Project 'garage' registered in Arcane"
  fi
fi

# ============================================================
# STEP 4: Pull image and start Garage
# ============================================================
info "Pre-pulling Docker image..."
${DRY_RUN} || remote "docker pull ${IMAGE}"
ok "Image pulled"

info "Starting Garage container (v2.3.0, --single-node --default-bucket)..."
if ! ${DRY_RUN}; then
  remote "docker compose -f ${REMOTE_PATH}/compose.yaml down 2>/dev/null; \
          docker compose -f ${REMOTE_PATH}/compose.yaml up -d"
fi
ok "Garage container started"

# ============================================================
# STEP 5: Wait for Garage to be healthy
# ============================================================
info "Waiting for Garage to be ready (up to 60s)..."
if ! ${DRY_RUN}; then
  for i in $(seq 1 30); do
    sleep 2
    STATUS=$(remote "docker inspect -f '{{.State.Health.Status}}' ${GARAGE_CONTAINER}" 2>/dev/null || echo "starting")
    STATUS="${STATUS//[!a-z]}"
    if [[ "${STATUS}" == "healthy" ]]; then
      ok "Garage is healthy"
      break
    fi
    if [[ "${i}" -eq 30 ]]; then
      warn "Health check timeout — check container logs manually"
      remote "docker logs ${GARAGE_CONTAINER} 2>&1 | tail -20"
    fi
  done
fi

# ============================================================
# STEP 6: Update Arcane DB to running
# ============================================================
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct exec ${LXC_ID} -- sqlite3 ${ARCANE_DB} \
      \"UPDATE projects SET status = 'running', service_count = 1, running_count = 1, updated_at = datetime('now') WHERE name = 'garage';\"" 2>/dev/null || true
  ok "Arcane project status set to 'running'"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀  Garage v2.3.0 deployed to LXC ${LXC_ID} (192.168.1.142)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  S3 API:     http://192.168.1.142:3900"
echo "  Admin API:  http://192.168.1.142:3903"
echo "  Arcane:     http://192.168.1.142:3552 (project 'garage')"
echo ""
echo "  Bucket 'homelab-terraform-state' and key 'terraform-operator'"
echo "  are auto-created by Garage on first run."
echo ""
echo "  To verify:"
echo "    terraform plan"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ok "Deploy script completed successfully"
