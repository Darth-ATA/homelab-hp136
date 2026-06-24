#!/usr/bin/env bash
# Create Garage bucket and API keys for Terraform state backend
#
# This script:
#   1. SSHes into LXC 101
#   2. Creates the bucket 'homelab-terraform-state'
#   3. Creates an API key with read/write/delete permissions on the bucket
#   4. Outputs the credentials to add to your local .env
#
# Usage: ./scripts/setup-garage-state.sh [--dry-run]
#
# Prerequisites:
#   - Garage container running on LXC 101
#   - GARAGE_ADMIN_TOKEN exported or in docker/garage/.env on LXC
#   - garage CLI available inside the container

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# --- Config ---
PROXMOX_HOST="192.168.1.134"
SSH_KEY="${HOME}/.ssh/homelab_key"
SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=no)
LXC_ID="101"
GARAGE_CONTAINER="garage"
BUCKET="homelab-terraform-state"
KEY_NAME="terraform-operator"
GARAGE_CLI="docker exec ${GARAGE_CONTAINER} garage"

# Local .env to update
ENV_FILE="${PROJECT_ROOT}/docker/garage/.env"

# Remote paths
GARAGE_PROJECT_DIR="/root/docker/arcane/data/projects/garage"
REMOTE_ENV="${GARAGE_PROJECT_DIR}/.env"

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

# --- Run remote command helper ---
remote() {
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "pct exec ${LXC_ID} -- ${*}"
}

# --- Step 1: Verify Garage container is running ---
info "Checking Garage container status..."
if ! ${DRY_RUN}; then
  GARAGE_STATUS="$(remote "docker inspect -f '{{.State.Status}}' ${GARAGE_CONTAINER}" 2>/dev/null || true)"
  if [[ "${GARAGE_STATUS}" != "running" ]]; then
    fail "Garage container is not running (status: ${GARAGE_STATUS:-unknown}). Deploy it first via scripts/deploy-garage.sh"
  fi
  ok "Garage container is running"
else
  ok "[DRY-RUN] Would check Garage container status"
fi

# --- Step 2: Create bucket ---
info "Creating bucket '${BUCKET}'..."
if ! ${DRY_RUN}; then
  BUCKET_EXISTS="$(remote "${GARAGE_CLI} bucket list" 2>/dev/null | grep -c "${BUCKET}" || true)"
  if [[ "${BUCKET_EXISTS}" -gt 0 ]]; then
    warn "Bucket '${BUCKET}' already exists — skipping creation"
  else
    remote "${GARAGE_CLI} bucket create ${BUCKET}"
    ok "Bucket '${BUCKET}' created"
  fi
else
  ok "[DRY-RUN] Would create bucket '${BUCKET}'"
fi

# --- Step 3: Create API key ---
info "Creating API key '${KEY_NAME}'..."
if ! ${DRY_RUN}; then
  # Check if key already exists
  KEY_EXISTS="$(remote "${GARAGE_CLI} key list" 2>/dev/null | grep -c "${KEY_NAME}" || true)"
  if [[ "${KEY_EXISTS}" -gt 0 ]]; then
    warn "Key '${KEY_NAME}' already exists"
    # Fetch existing key info
    KEY_INFO="$(remote "${GARAGE_CLI} key info ${KEY_NAME}")"
  else
    KEY_INFO="$(remote "${GARAGE_CLI} key create ${KEY_NAME}")"
    ok "Key '${KEY_NAME}' created"
  fi
else
  KEY_INFO='[DRY-RUN] Would create key and capture credentials'
fi

# --- Step 4: Allow key on bucket (read, write, delete) ---
info "Granting permissions on bucket '${BUCKET}'..."
if ! ${DRY_RUN}; then
  remote "${GARAGE_CLI} bucket allow ${BUCKET} --key ${KEY_NAME} --read --write --delete"
  ok "Permissions granted"
else
  ok "[DRY-RUN] Would grant read/write/delete to ${KEY_NAME} on ${BUCKET}"
fi

# --- Step 5: Extract and display credentials ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔑  Terraform State Backend Credentials"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! ${DRY_RUN}; then
  # Parse key info output for access key ID and secret key
  ACCESS_KEY_ID="$(echo "${KEY_INFO}" | grep -oP '(?<=Key ID: )\w+' || echo "")"
  SECRET_ACCESS_KEY="$(echo "${KEY_INFO}" | grep -oP '(?<=Secret key: )\w+' || echo "")"

  echo ""
  echo "  Access Key ID:       ${ACCESS_KEY_ID}"
  echo "  Secret Access Key:   ${SECRET_ACCESS_KEY}"
  echo ""

  # Update local .env file
  if [[ -f "${ENV_FILE}" ]]; then
    echo "  Updating ${ENV_FILE}..."
    if [[ -n "${ACCESS_KEY_ID}" ]]; then
      # Replace values in .env (macOS/BSD compatible sed)
      sed -i '' "s/^AWS_ACCESS_KEY_ID=.*/AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}/" "${ENV_FILE}"
    fi
    if [[ -n "${SECRET_ACCESS_KEY}" ]]; then
      sed -i '' "s/^AWS_SECRET_ACCESS_KEY=.*/AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}/" "${ENV_FILE}"
    fi
    ok "${ENV_FILE} updated"
  else
    warn "Local .env not found at ${ENV_FILE}"
    warn "  Create it from docker/garage/.env.example and add:"
    warn "  AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}"
    warn "  AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}"
  fi

  # Also update the remote .env on LXC
  if [[ -n "${ACCESS_KEY_ID}" ]] && [[ -n "${SECRET_ACCESS_KEY}" ]]; then
    info "Updating remote .env on LXC..."
    remote "sed -i 's/^AWS_ACCESS_KEY_ID=.*/AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}/' ${REMOTE_ENV}"
    remote "sed -i 's/^AWS_SECRET_ACCESS_KEY=.*/AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}/' ${REMOTE_ENV}"
    ok "Remote .env updated"
  fi

  echo ""
  echo "  ⚡  Next step: export the credentials and migrate Terraform state:"
  echo "      export AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}"
  echo "      export AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}"
  echo "      cd ${PROJECT_ROOT} && terraform init -migrate-state"
else
  echo ""
  echo "  [DRY-RUN] Would create key and display credentials"
  echo "  [DRY-RUN] Would update ${ENV_FILE}"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ok "Setup script completed"
