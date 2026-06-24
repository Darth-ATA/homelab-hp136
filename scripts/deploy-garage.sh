#!/usr/bin/env bash
# Deploy Garage S3-compatible storage on LXC 101 — fully automated
#
# This script does EVERYTHING:
#   1. Copies compose.yaml, garage.toml, .env to LXC 101
#   2. Registers the project in Arcane (SQLite)
#   3. Starts Garage via docker compose
#   4. Configures the cluster layout (single-node)
#   5. Creates the Terraform state bucket + API key
#   6. Updates .env files (local + remote)
#   7. Runs terraform init -migrate-state
#
# Usage: ./scripts/deploy-garage.sh [--dry-run]
#
# Prerequisites:
#   - SSH key at ~/.ssh/homelab_key
#   - Proxmox host at 192.168.1.134
#   - LXC 101 (docker) running
#   - docker/garage/.env with GARAGE_ADMIN_TOKEN + GARAGE_METRICS_TOKEN

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# --- Config ---
PROXMOX_HOST="192.168.1.134"
SSH_KEY="${HOME}/.ssh/homelab_key"
SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=no)
LXC_ID="101"
GARAGE_CONTAINER="garage"
GARAGE_PROJECT_DIR="/root/docker/arcane/data/projects/garage"
REMOTE_PATH="/root/docker/arcane/data/projects/garage"
COMPOSE_SRC="${PROJECT_ROOT}/docker/garage/compose.yml"
GARAGE_TOML_SRC="${PROJECT_ROOT}/docker/garage/garage.toml"
ENV_SRC="${PROJECT_ROOT}/docker/garage/.env"
IMAGE="dxflrs/garage:v1.0.1"
BUCKET="homelab-terraform-state"
KEY_NAME="terraform-operator"
LOCAL_ENV="${PROJECT_ROOT}/docker/garage/.env"
ARCANE_DB="/root/docker/arcane/data/arcane.db"

# --- Helpers ---
info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[OK]\033[0m   %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

remote() {
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "pct exec ${LXC_ID} -- ${*}"
}

remote_ct() {
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "pct exec ${LXC_ID} -- docker exec ${GARAGE_CONTAINER} ${*}"
}

# --- Dry-run ---
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  info "DRY RUN — no changes will be made"
fi

# --- Pre-flight checks ---
if [[ ! -f "${SSH_KEY}" ]]; then
  fail "SSH key not found at ${SSH_KEY}"
fi
if [[ ! -f "${COMPOSE_SRC}" ]]; then
  fail "Compose file not found at ${COMPOSE_SRC}"
fi
if [[ ! -f "${GARAGE_TOML_SRC}" ]]; then
  fail "garage.toml not found at ${GARAGE_TOML_SRC}"
fi
if [[ ! -f "${ENV_SRC}" ]]; then
  fail "Local .env not found at ${ENV_SRC}. Create it from docker/garage/.env.example first."
fi

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

info "Copying compose.yaml..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct push ${LXC_ID} ${COMPOSE_SRC} ${REMOTE_PATH}/compose.yaml"
fi

info "Copying garage.toml..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct push ${LXC_ID} ${GARAGE_TOML_SRC} ${REMOTE_PATH}/garage.toml"
fi

info "Copying .env..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct push ${LXC_ID} ${ENV_SRC} ${REMOTE_PATH}/.env"
fi
ok "Files copied to ${REMOTE_PATH}"

# ============================================================
# STEP 3: Register project in Arcane SQLite DB
# ============================================================
info "Registering project in Arcane..."
if ! ${DRY_RUN}; then
  PROJECT_EXISTS=$(ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct exec ${LXC_ID} -- sqlite3 ${ARCANE_DB} \"SELECT COUNT(*) FROM projects WHERE name = 'garage';\"" 2>/dev/null || echo "0")
  PROJECT_EXISTS="${PROJECT_EXISTS//[!0-9]/}"

  if [[ "${PROJECT_EXISTS}" -gt 0 ]]; then
    # Update existing project (e.g. from "unknown" to "stopped")
    ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
      "pct exec ${LXC_ID} -- sqlite3 ${ARCANE_DB} \"UPDATE projects SET status = 'stopped', updated_at = datetime('now') WHERE name = 'garage';\"" 2>/dev/null || true
    warn "Project 'garage' already exists in Arcane DB — reset to 'stopped'"
  else
    # Create new project
    PROJECT_ID=$(ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
      "pct exec ${LXC_ID} -- python3 -c \"import uuid; print(uuid.uuid4())\"" 2>/dev/null || echo "$(uuidgen)")
    ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
      "pct exec ${LXC_ID} -- sqlite3 ${ARCANE_DB} \"INSERT INTO projects (id, name, dir_name, path, status, service_count, running_count, created_at) VALUES ('${PROJECT_ID}', 'garage', 'garage', '/app/data/projects/garage', 'stopped', 0, 0, datetime('now'));\""
    ok "Project 'garage' registered in Arcane"
  fi
fi

# ============================================================
# STEP 4: Pull image and start Garage
# ============================================================
info "Pre-pulling Docker image..."
${DRY_RUN} || remote "docker pull ${IMAGE}"
ok "Image pulled"

info "Starting Garage container..."
if ! ${DRY_RUN}; then
  remote "docker compose -f ${REMOTE_PATH}/compose.yaml down 2>/dev/null; \
          docker compose -f ${REMOTE_PATH}/compose.yaml up -d"
fi
ok "Garage container started"

# ============================================================
# STEP 5: Wait for Garage to be healthy
# ============================================================
info "Waiting for Garage to be ready (up to 30s)..."
if ! ${DRY_RUN}; then
  for i in $(seq 1 15); do
    sleep 2
    STATUS=$(remote "docker inspect -f '{{.State.Health.Status}}' ${GARAGE_CONTAINER}" 2>/dev/null || echo "starting")
    STATUS="${STATUS//[!a-z]}"
    if [[ "${STATUS}" == "healthy" ]]; then
      ok "Garage is healthy"
      break
    fi
    if [[ "${STATUS}" == "unhealthy" ]]; then
      warn "Health check not passing yet (attempt ${i}/15)..."
    fi
  done
fi

# ============================================================
# STEP 6: Configure cluster layout
# ============================================================
info "Configuring Garage cluster layout..."
if ! ${DRY_RUN}; then
  # Get node ID
  NODE_ID=$(remote_ct "/garage node id" 2>&1 | grep -oE '[0-9a-f]{64}')

  # Remove any stale staged layout
  remote_ct "/garage layout revert" 2>/dev/null || true
  # Assign role
  remote_ct "/garage layout assign --capacity 10G --zone dc1 ${NODE_ID}" 2>&1 | grep -v "handshake\|established\|INFO\|WARN" || true
  # Apply
  remote_ct "/garage layout apply --version 1" 2>&1 | grep -v "handshake\|established\|INFO\|WARN" || true
  ok "Cluster layout configured (single-node, 10G, zone dc1)"
fi

# ============================================================
# STEP 7: Create bucket and API key
# ============================================================
info "Setting up bucket '${BUCKET}' and key '${KEY_NAME}'..."
if ! ${DRY_RUN}; then
  # Create bucket (idempotent)
  remote_ct "/garage bucket create ${BUCKET}" 2>&1 | grep -v "handshake\|established\|INFO\|WARN" || true

  # Create key (idempotent)
  remote_ct "/garage key create ${KEY_NAME}" 2>&1 | grep -v "handshake\|established\|INFO\|WARN" || true

  # Grant permissions
  remote_ct "/garage bucket allow ${BUCKET} --key ${KEY_NAME} --read --write" 2>&1 | grep -v "handshake\|established\|INFO\|WARN" || true

  # Extract credentials
  KEY_INFO=$(remote_ct "/garage key info ${KEY_NAME}" 2>&1)
  ACCESS_KEY_ID=$(echo "${KEY_INFO}" | grep -oP '(?<=Key ID: )\S+' || echo "")
  SECRET_ACCESS_KEY=$(echo "${KEY_INFO}" | grep -oP '(?<=Secret key: )\S+' || echo "")
  ok "Bucket and key created"
fi

# ============================================================
# STEP 8: Update .env files (local + remote)
# ============================================================
if [[ -n "${ACCESS_KEY_ID:-}" ]] && [[ -n "${SECRET_ACCESS_KEY:-}" ]] && ! ${DRY_RUN}; then
  info "Updating .env files with credentials..."

  # Remote .env
  remote "sed -i 's/^AWS_ACCESS_KEY_ID=.*/AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}/' ${REMOTE_PATH}/.env"
  remote "sed -i 's/^AWS_SECRET_ACCESS_KEY=.*/AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}/' ${REMOTE_PATH}/.env"
  ok "Remote .env updated"

  # Local .env (macOS/BSD sed)
  if [[ -f "${LOCAL_ENV}" ]]; then
    sed -i '' "s/^AWS_ACCESS_KEY_ID=.*/AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}/" "${LOCAL_ENV}"
    sed -i '' "s/^AWS_SECRET_ACCESS_KEY=.*/AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}/" "${LOCAL_ENV}"
    ok "Local .env updated"
  fi
fi

# ============================================================
# STEP 9: Update Arcane DB to running + display summary
# ============================================================
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct exec ${LXC_ID} -- sqlite3 ${ARCANE_DB} \"UPDATE projects SET status = 'running', service_count = 1, running_count = 1, updated_at = datetime('now') WHERE name = 'garage';\"" 2>/dev/null || true
  ok "Arcane project status set to 'running'"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀  Garage deployed to LXC ${LXC_ID} (192.168.1.142)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Bucket:     ${BUCKET}"
echo "  Key name:   ${KEY_NAME}"
echo "  Access ID:  ${ACCESS_KEY_ID:-<see .env>}"
echo "  S3 API:     http://192.168.1.142:3900"
echo "  Admin API:  http://192.168.1.142:3903"
echo "  Arcane:     http://192.168.1.142:3552 (project 'garage')"
echo ""
echo "  Next step: migrate Terraform state:"
echo ""
echo "    source ${LOCAL_ENV}"
echo "    cd ${PROJECT_ROOT}"
echo "    terraform init -migrate-state"
echo "    terraform plan"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ok "Deploy script completed successfully"
