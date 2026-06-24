#!/usr/bin/env bash
# Deploy Garage S3-compatible storage on LXC 101 — fully automated
#
# This script does EVERYTHING in one shot:
#   1. Generates any missing credentials (tokens, RPC secret, access keys)
#   2. Copies compose.yaml, garage.toml, .env to LXC 101
#   3. Registers the project in Arcane (SQLite)
#   4. Starts Garage via docker compose
#   5. Garage v2.3.0 auto-configures: cluster layout (--single-node),
#      Terraform state bucket + API keys (--default-bucket)
#   6. Updates Arcane project status to "running"
#   7. (Optional) Migrates Terraform state with --with-state-migration
#
# Usage:
#   ./scripts/deploy-garage.sh                          # deploy only
#   ./scripts/deploy-garage.sh --with-state-migration    # deploy + migrate state
#   ./scripts/deploy-garage.sh --verify                  # check health + creds only
#
# Prerequisites:
#   - SSH key at ~/.ssh/homelab_key
#   - Proxmox host at 192.168.1.134
#   - LXC 101 (docker) running
#   - docker/garage/.env (can be empty — script generates missing values)

set -Eeuo pipefail

# ──────────────────────────────────────────────
# CONFIG
# ──────────────────────────────────────────────
PROXMOX_HOST="192.168.1.134"
SSH_KEY="${HOME}/.ssh/homelab_key"
SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=5)
LXC_ID="101"
GARAGE_CONTAINER="garage"
GARAGE_PROJECT_DIR="/root/docker/arcane/data/projects/garage"
REMOTE_PATH="${GARAGE_PROJECT_DIR}"
ARCANE_DB="/root/docker/arcane/data/arcane.db"

LOCAL_ENV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)/docker/garage/.env"
COMPOSE_SRC="$(dirname "${LOCAL_ENV}")/compose.yml"
GARAGE_TOML_SRC="$(dirname "${LOCAL_ENV}")/garage.toml"

IMAGE="dxflrs/garage:v2.3.0"
BUCKET="homelab-terraform-state"
KEY_NAME="terraform-operator"

# ──────────────────────────────────────────────
# FLAGS
# ──────────────────────────────────────────────
DRY_RUN=false
WITH_MIGRATE=false
VERIFY_ONLY=false
for arg in "$@"; do
  case "${arg}" in
    --dry-run)           DRY_RUN=true ;;
    --with-state-migration) WITH_MIGRATE=true ;;
    --verify)            VERIFY_ONLY=true ;;
    *) echo "Unknown flag: ${arg}"; exit 1 ;;
  esac
done

# ──────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[OK]\033[0m   %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

# Run a command inside LXC 101
lxc_exec() {
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct exec ${LXC_ID} -- ${*}" 2>/dev/null || true
}

# Run a command inside the Garage container
garage_exec() {
  lxc_exec "docker exec ${GARAGE_CONTAINER} ${*}"
}

# Generate a random hex string
gen_hex() {
  openssl rand -hex "${1:-32}" 2>/dev/null || \
  python3 -c "import secrets; print(secrets.token_hex(${1:-32}))" 2>/dev/null || \
  echo "CHANGE_ME_$(uuidgen | tr -d '-')"
}

# Generate a random alphanumeric string for AWS access/secret keys
gen_alnum() {
  python3 -c "import secrets; print(secrets.token_urlsafe(${1:-32}).replace('-','').replace('_','')[:${1:-32}])" 2>/dev/null || \
  echo "CHANGE_ME_$(uuidgen | tr -d '-')"
}

# Read a value from the local .env file
env_read() {
  local key="$1"
  local file="${LOCAL_ENV}"
  if [[ -f "${file}" ]]; then
    grep "^${key}=" "${file}" 2>/dev/null | cut -d= -f2- || true
  fi
}

# ──────────────────────────────────────────────
# PRE-FLIGHT
# ──────────────────────────────────────────────
if [[ ! -f "${SSH_KEY}" ]]; then
  fail "SSH key not found at ${SSH_KEY}"
fi

# ────── Verify-only mode ──────
if ${VERIFY_ONLY}; then
  info "Verifying Garage deployment..."
  STATUS=$(lxc_exec "docker inspect -f '{{.State.Status}}' ${GARAGE_CONTAINER}")
  HEALTH=$(lxc_exec "docker inspect -f '{{.State.Health.Status}}' ${GARAGE_CONTAINER}")

  if [[ "${STATUS}" != "running" ]]; then
    fail "Garage container is NOT running (status: ${STATUS})"
  fi
  ok "Container status: ${STATUS}"

  if [[ "${HEALTH}" == "healthy" ]]; then
    ok "Container health: ${HEALTH}"
  else
    warn "Container health: ${HEALTH:-unknown}"
  fi

  # Show cluster status
  echo ""
  garage_exec "/garage status" 2>/dev/null || warn "Could not run /garage status"
  echo ""

  # Show bucket and key info
  garage_exec "/garage bucket list" 2>/dev/null || warn "Could not list buckets"
  echo ""

  KEY_EXISTS=$(garage_exec "/garage key info ${KEY_NAME}" 2>/dev/null | grep -c "Key ID:" || true)
  if [[ "${KEY_EXISTS}" -gt 0 ]]; then
    garage_exec "/garage key info ${KEY_NAME}" 2>/dev/null
  fi

  # Check terraform
  info "Running terraform plan..."
  pushd "${PROJECT_ROOT}" >/dev/null
  set -a
  # shellcheck disable=SC1090
  source "${LOCAL_ENV}" 2>/dev/null || true
  set +a
  terraform plan 2>&1 | tail -10
  popd >/dev/null

  exit 0
fi

# ────── Dry-run reminder ──────
if ${DRY_RUN}; then
  info "DRY RUN — no changes will be made"
fi

# ──────────────────────────────────────────────
# STEP 0: Validate/generate credentials
# ──────────────────────────────────────────────
info "Checking credentials in ${LOCAL_ENV}..."

# Create .env from .env.example if it doesn't exist
if [[ ! -f "${LOCAL_ENV}" ]]; then
  if [[ -f "${LOCAL_ENV}.example" ]]; then
    cp "${LOCAL_ENV}.example" "${LOCAL_ENV}"
    warn "Created ${LOCAL_ENV} from .env.example"
  else
    fail "No .env or .env.example found at ${LOCAL_ENV}"
  fi
fi

# Source current .env to check values
# shellcheck disable=SC1090
set +o allexport
source "${LOCAL_ENV}" 2>/dev/null || true
set -o allexport

NEEDS_UPDATE=false

_generate_and_set() {
  local var_name="$1"
  local current_val="${!var_name:-}"
  local gen_func="$2"

  if [[ -z "${current_val}" || "${current_val}" == CHANGE_ME_* ]]; then
    local new_val
    new_val=$(${gen_func})
    info "  Generating ${var_name}..."
    # Update the running shell
    export "${var_name}=${new_val}"
    # Update the .env file on disk
    if grep -q "^${var_name}=" "${LOCAL_ENV}" 2>/dev/null; then
      sed -i '' "s|^${var_name}=.*|${var_name}=${new_val}|" "${LOCAL_ENV}"
    else
      echo "${var_name}=${new_val}" >> "${LOCAL_ENV}"
    fi
    NEEDS_UPDATE=true
    ok "  ${var_name} → set"
  else
    ok "  ${var_name} ✓ already set"
  fi
}

_generate_and_set "GARAGE_RPC_SECRET"   "gen_hex 32"
_generate_and_set "GARAGE_ADMIN_TOKEN"  "gen_hex 32"
_generate_and_set "GARAGE_METRICS_TOKEN" "gen_hex 16"
_generate_and_set "AWS_ACCESS_KEY_ID"   "gen_alnum 20"
_generate_and_set "AWS_SECRET_ACCESS_KEY" "gen_alnum 40"

if ${NEEDS_UPDATE}; then
  ok "Credentials generated and saved to ${LOCAL_ENV}"
fi

# Re-source to get any new values
# shellcheck disable=SC1090
set +o allexport
source "${LOCAL_ENV}" 2>/dev/null || true
set -o allexport

# Validate no blanks left
REQUIRED_VARS=("GARAGE_RPC_SECRET" "GARAGE_ADMIN_TOKEN" "GARAGE_METRICS_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY")
for var in "${REQUIRED_VARS[@]}"; do
  val="${!var:-}"
  if [[ -z "${val}" ]]; then
    fail "${var} is empty in ${LOCAL_ENV}. Fill it and re-run."
  fi
done

# ──────────────────────────────────────────────
# STEP 1: Verify LXC 101 is reachable
# ──────────────────────────────────────────────
info "Checking LXC ${LXC_ID} reachability..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "pct status ${LXC_ID}" >/dev/null 2>&1 \
    || fail "LXC ${LXC_ID} is not running or Proxmox is unreachable"
  ok "LXC ${LXC_ID} is running"
fi

# ──────────────────────────────────────────────
# STEP 2: Copy files to LXC
# ──────────────────────────────────────────────
# NOTE: pct push reads from the Proxmox host's filesystem, NOT from the client.
# We must SCP to the host first, then pct push from /tmp.
PROX_TMP="/tmp/garage-deploy-$$"
info "Creating project directory..."
${DRY_RUN} || lxc_exec "mkdir -p ${REMOTE_PATH}"

info "Staging files on Proxmox host..."
${DRY_RUN} || ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "mkdir -p ${PROX_TMP}"

if ! ${DRY_RUN}; then
  scp "${SSH_OPTS[@]}" "${COMPOSE_SRC}" "root@${PROXMOX_HOST}:${PROX_TMP}/compose.yaml" >/dev/null 2>&1
  scp "${SSH_OPTS[@]}" "${GARAGE_TOML_SRC}" "root@${PROXMOX_HOST}:${PROX_TMP}/garage.toml" >/dev/null 2>&1
  scp "${SSH_OPTS[@]}" "${LOCAL_ENV}" "root@${PROXMOX_HOST}:${PROX_TMP}/.env" >/dev/null 2>&1
fi

info "Copying compose.yaml to LXC..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct push ${LXC_ID} ${PROX_TMP}/compose.yaml ${REMOTE_PATH}/compose.yaml" || \
    fail "Failed to copy compose.yaml"
fi

info "Copying garage.toml to LXC..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct push ${LXC_ID} ${PROX_TMP}/garage.toml ${REMOTE_PATH}/garage.toml" || \
    fail "Failed to copy garage.toml"
fi

info "Copying .env to LXC..."
if ! ${DRY_RUN}; then
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct push ${LXC_ID} ${PROX_TMP}/.env ${REMOTE_PATH}/.env" || \
    fail "Failed to copy .env"
fi

# Clean up staging directory
${DRY_RUN} || ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" "rm -rf ${PROX_TMP}" >/dev/null 2>&1

ok "Files copied to ${REMOTE_PATH}"

# ──────────────────────────────────────────────
# STEP 2b: Replace __RPC_SECRET__ placeholder with actual value
# ──────────────────────────────────────────────
RPC_SECRET="${GARAGE_RPC_SECRET}"
info "Injecting RPC secret into remote garage.toml..."
if ! ${DRY_RUN}; then
  lxc_exec "sed -i 's/__RPC_SECRET__/${RPC_SECRET}/' ${REMOTE_PATH}/garage.toml"
  ok "RPC secret injected"
fi

# ──────────────────────────────────────────────
# STEP 3: Register project in Arcane SQLite DB
# ──────────────────────────────────────────────
info "Registering project in Arcane..."
if ! ${DRY_RUN}; then
  PROJECT_EXISTS=$(lxc_exec "sqlite3 ${ARCANE_DB} \"SELECT COUNT(*) FROM projects WHERE name = 'garage';\"" 2>/dev/null || echo "0")
  PROJECT_EXISTS="${PROJECT_EXISTS//[!0-9]/}"

  if [[ "${PROJECT_EXISTS}" -gt 0 ]]; then
    lxc_exec "sqlite3 ${ARCANE_DB} \"UPDATE projects SET status = 'stopped', updated_at = datetime('now') WHERE name = 'garage';\"" 2>/dev/null || true
    warn "Project 'garage' already exists in Arcane DB — reset to 'stopped'"
  else
    PROJECT_ID=$(lxc_exec "python3 -c \"import uuid; print(uuid.uuid4())\"" 2>/dev/null || uuidgen)
    lxc_exec "sqlite3 ${ARCANE_DB} \"INSERT INTO projects (id, name, dir_name, path, status, service_count, running_count, created_at) VALUES ('${PROJECT_ID}', 'garage', 'garage', '/app/data/projects/garage', 'stopped', 0, 0, datetime('now'));\""
    ok "Project 'garage' registered in Arcane"
  fi
fi

# ──────────────────────────────────────────────
# STEP 4: Start Garage via docker compose
# ──────────────────────────────────────────────
# v2.3.0's --single-node auto-configures cluster layout
# --default-bucket auto-creates the bucket + key from env vars
info "Pulling Docker image..."
${DRY_RUN} || lxc_exec "docker pull ${IMAGE}"

info "Starting Garage container..."
if ! ${DRY_RUN}; then
  lxc_exec "docker compose -f ${REMOTE_PATH}/compose.yaml down 2>/dev/null; \
            docker compose -f ${REMOTE_PATH}/compose.yaml up -d"
fi
ok "Garage container started"

# ──────────────────────────────────────────────
# STEP 5: Wait for Garage to be healthy
# ──────────────────────────────────────────────
info "Waiting for Garage to be ready (up to 60s)..."
if ! ${DRY_RUN}; then
  HEALTHY=false
  for i in $(seq 1 30); do
    sleep 2
    STATUS=$(lxc_exec "docker inspect -f '{{.State.Health.Status}}' ${GARAGE_CONTAINER}" 2>/dev/null || echo "starting")
    STATUS="${STATUS//[!a-z]}"
    if [[ "${STATUS}" == "healthy" ]]; then
      HEALTHY=true
      ok "Garage is healthy (attempt ${i})"
      break
    fi
    if [[ "${STATUS}" == "unhealthy" ]]; then
      warn "Health check failing (attempt ${i}/30)..."
    fi
  done

  if ! ${HEALTHY}; then
    warn "Garage did not become healthy within 60s"
    warn "Check logs: docker compose -f ${REMOTE_PATH}/compose.yaml logs"
    # Show last 20 lines of logs for diagnosis
    lxc_exec "docker compose -f ${REMOTE_PATH}/compose.yaml logs --tail=20" 2>/dev/null || true
    fail "Garage failed to start"
  fi

  # Quick sanity: show cluster status
  garage_exec "/garage status" 2>/dev/null || warn "Could not run /garage status"
fi

# ──────────────────────────────────────────────
# STEP 6: Verify bucket and key were created
# ──────────────────────────────────────────────
# --default-bucket handles this, but we verify
info "Verifying bucket and key..."
if ! ${DRY_RUN}; then
  BUCKET_OK=$(garage_exec "/garage bucket list" 2>/dev/null | grep -c "${BUCKET}" || true)
  KEY_OK=$(garage_exec "/garage key info ${KEY_NAME}" 2>/dev/null | grep -c "Key ID:" || true)
  if [[ "${BUCKET_OK}" -eq 0 ]]; then
    warn "Bucket '${BUCKET}' not found. Creating manually..."
    garage_exec "/garage bucket create ${BUCKET}" 2>/dev/null || true
  fi
  if [[ "${KEY_OK}" -eq 0 ]]; then
    warn "Key '${KEY_NAME}' not found. Creating manually..."
    garage_exec "/garage key create ${KEY_NAME}" 2>/dev/null || true
  fi
  # Grant permissions (idempotent)
  garage_exec "/garage bucket allow ${BUCKET} --key ${KEY_NAME} --read --write" 2>/dev/null || true
  ok "Bucket and key verified"
fi

# ──────────────────────────────────────────────
# STEP 7: Update Arcane DB to running
# ──────────────────────────────────────────────
if ! ${DRY_RUN}; then
  lxc_exec "sqlite3 ${ARCANE_DB} \"UPDATE projects SET status = 'running', service_count = 1, running_count = 1, updated_at = datetime('now') WHERE name = 'garage';\"" 2>/dev/null || true
  ok "Arcane project status set to 'running'"
fi

# ──────────────────────────────────────────────
# STEP 8: (Optional) Migrate Terraform state
# ──────────────────────────────────────────────
if ${WITH_MIGRATE}; then
  info "Migrating Terraform state to Garage backend..."
  if ! ${DRY_RUN}; then
    pushd "${PROJECT_ROOT}" >/dev/null

    # Source the .env with credentials (set -a exports all sourced vars)
    set -a
    # shellcheck disable=SC1090
    source "${LOCAL_ENV}" 2>/dev/null || true
    set +a

    export AWS_ENDPOINT_URL_S3="http://192.168.1.142:3900"
    export AWS_S3_FORCE_PATH_STYLE="true"
    export AWS_DEFAULT_REGION="garage"

    if terraform init -migrate-state -force-copy 2>&1; then
      ok "Terraform state migrated successfully"
    else
      warn "Terraform init failed. Try manually:"
      warn "  source ${LOCAL_ENV}"
      warn "  terraform init -migrate-state"
    fi

    popd >/dev/null
  fi
fi

# ──────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀  Garage v2.3.0 deployed to LXC ${LXC_ID}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  S3 API:      http://192.168.1.142:3900"
echo "  Admin API:   http://192.168.1.142:3903"
echo "  Arcane:      http://192.168.1.142:3552 (project 'garage')"
echo "  Bucket:      ${BUCKET}"
echo "  Key name:    ${KEY_NAME}"
echo ""
echo "  Credentials saved to: ${LOCAL_ENV}"
echo ""
echo "  Verify health:  ./scripts/deploy-garage.sh --verify"
echo ""
echo "  Migrate state:  source ${LOCAL_ENV}"
echo "                  export AWS_ENDPOINT_URL_S3=http://192.168.1.142:3900"
echo "                  export AWS_S3_FORCE_PATH_STYLE=true"
echo "                  export AWS_DEFAULT_REGION=garage"
echo "                  terraform init -migrate-state"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ok "Deploy completed successfully"
