#!/usr/bin/env bash
# Deploy Garage S3-compatible storage on LXC 101 via Arcane
#
# This script:
#   1. SSHes into Proxmox host, then pct enters LXC 101
#   2. Creates the Arcane project directory for Garage
#   3. Copies the compose.yml reference to the LXC
#   4. Creates a minimal garage.toml config
#   5. Provides instructions to complete setup via Arcane UI
#
# Usage: ./scripts/deploy-garage.sh [--dry-run]
#
# Prerequisites:
#   - SSH key at ~/.ssh/homelab_key
#   - Proxmox host at 192.168.1.134
#   - LXC 101 (docker) running
#   - docker/garage/.env populated with credentials

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# --- Config ---
PROXMOX_HOST="192.168.1.134"
SSH_KEY="${HOME}/.ssh/homelab_key"
SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=no)
LXC_ID="101"
GARAGE_PROJECT_DIR="/root/docker/arcane/data/projects/garage"
COMPOSE_SRC="${PROJECT_ROOT}/docker/garage/compose.yml"
ENV_SRC="${PROJECT_ROOT}/docker/garage/.env"
REMOTE_COMPOSE="${GARAGE_PROJECT_DIR}/compose.yml"
REMOTE_ENV="${GARAGE_PROJECT_DIR}/.env"
IMAGE="dxflrs/garage:v1.0.1"

# --- Helper ---
info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[OK]\033[0m   %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

# --- Dry-run flag ---
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

if [[ ! -f "${ENV_SRC}" ]]; then
  warn "Local .env not found at ${ENV_SRC}"
  warn "Create it from docker/garage/.env.example before deploying"
fi

# --- Step 1: Verify LXC 101 is reachable ---
info "Checking LXC ${LXC_ID} reachability..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "pct status ${LXC_ID}" >/dev/null 2>&1 \
    || fail "LXC ${LXC_ID} is not running or Proxmox is unreachable"
  ok "LXC ${LXC_ID} is running"
else
  ok "[DRY-RUN] Would check LXC ${LXC_ID} status"
fi

# --- Step 2: Create Arcane project directory on LXC ---
info "Creating Arcane project directory at ${GARAGE_PROJECT_DIR}..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct exec ${LXC_ID} -- mkdir -p ${GARAGE_PROJECT_DIR}"
  ok "Directory created"
else
  ok "[DRY-RUN] Would create directory ${GARAGE_PROJECT_DIR}"
fi

# --- Step 3: Copy compose.yml to LXC ---
info "Copying compose.yml to LXC..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct push ${LXC_ID} ${COMPOSE_SRC} ${REMOTE_COMPOSE}"
  ok "compose.yml copied"
else
  ok "[DRY-RUN] Would copy ${COMPOSE_SRC} → ${REMOTE_COMPOSE}"
fi

# --- Step 4: Copy .env to LXC (if exists) ---
if [[ -f "${ENV_SRC}" ]]; then
  info "Copying .env to LXC..."
  if ! ${DRY_RUN}; then
    ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
      "pct push ${LXC_ID} ${ENV_SRC} ${REMOTE_ENV}"
    ok ".env copied"
  else
    ok "[DRY-RUN] Would copy ${ENV_SRC} → ${REMOTE_ENV}"
  fi
else
  warn "Skipping .env copy — file not found locally"
  warn "  Create it from docker/garage/.env.example and re-run this script"
fi

# --- Step 5: Pull image ahead of time ---
info "Pre-pulling Docker image (${IMAGE})..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct exec ${LXC_ID} -- docker pull ${IMAGE}"
  ok "Image pulled"
else
  ok "[DRY-RUN] Would pull image ${IMAGE}"
fi

# --- Step 6: Instructions for Arcane UI ---
cat <<INSTRUCTIONS

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🚀  Garage deployed to LXC ${LXC_ID}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Next steps:

  1. Open Arcane UI: http://192.168.1.142:3552
  2. Add project "garage" pointing to:
     ${GARAGE_PROJECT_DIR}
  3. Click "Deploy" to start the container
  4. Verify it's running:
     ssh -i ${SSH_KEY} root@${PROXMOX_HOST} "pct exec ${LXC_ID} -- docker ps"

  5. Configure the bucket and API keys:
     ./scripts/setup-garage-state.sh

  6. Finally, migrate Terraform state:
     Follow docs/terraform-state-migration.md

  ⚠️  Make sure docker/garage/.env has valid credentials before starting
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INSTRUCTIONS

ok "Deploy script completed"
