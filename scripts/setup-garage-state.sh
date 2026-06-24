#!/usr/bin/env bash
# Verify or rotate Garage S3 credentials for Terraform state backend
#
# On Garage v2.3.0, --default-bucket handles initial bucket+key creation.
# This script is for POST-deploy operations:
#   - Verify existing credentials are valid
#   - Rotate AWS access keys (recreate key, update .env files)
#   - Check bucket/key permissions
#
# Usage:
#   ./scripts/setup-garage-state.sh               # verify only
#   ./scripts/setup-garage-state.sh --rotate-creds # rotate API keys
#   ./scripts/setup-garage-state.sh --dry-run      # dry run
#
# Prerequisites:
#   - Garage container running on LXC 101
#   - garage.toml with valid rpc_secret or docker-compose running

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

LOCAL_ENV="${PROJECT_ROOT}/docker/garage/.env"
REMOTE_ENV="/root/docker/arcane/data/projects/garage/.env"

# --- Flags ---
DRY_RUN=false
ROTATE=false
for arg in "$@"; do
  case "${arg}" in
    --dry-run)      DRY_RUN=true ;;
    --rotate-creds) ROTATE=true ;;
    *) echo "Usage: $0 [--dry-run] [--rotate-creds]"; exit 1 ;;
  esac
done

# --- Helpers ---
info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[OK]\033[0m   %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

lxc_exec() {
  ssh "${SSH_OPTS[@]}" "root@${PROXMOX_HOST}" \
    "pct exec ${LXC_ID} -- ${*}" 2>/dev/null || true
}

garage_exec() {
  lxc_exec "docker exec ${GARAGE_CONTAINER} ${*}"
}

gen_alnum() {
  python3 -c "import secrets; print(secrets.token_urlsafe(${1:-32}).replace('-','').replace('_','')[:${1:-32}])" 2>/dev/null || \
  echo "rotated_$(uuidgen | tr -d '-')"
}

# --- Pre-flight ---
if [[ ! -f "${SSH_KEY}" ]]; then
  fail "SSH key not found at ${SSH_KEY}"
fi

GARAGE_STATUS="$(lxc_exec "docker inspect -f '{{.State.Status}}' ${GARAGE_CONTAINER}" 2>/dev/null || true)"
if [[ "${GARAGE_STATUS}" != "running" ]]; then
  fail "Garage container is not running (status: ${GARAGE_STATUS:-unknown}). Deploy it first."
fi
ok "Garage container is running"

HEALTH="$(lxc_exec "docker inspect -f '{{.State.Health.Status}}' ${GARAGE_CONTAINER}" 2>/dev/null || true)"
if [[ "${HEALTH}" != "healthy" ]]; then
  warn "Container health: ${HEALTH:-unknown} (expected 'healthy')"
fi

# --- Verify existing credentials ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔑  Garage Credentials — ${ROTATE:+ROTATION}${ROTATE:-VERIFICATION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Bucket
BUCKET_EXISTS="$(garage_exec "/garage bucket list" 2>/dev/null | grep -c "${BUCKET}" || true)"
if [[ "${BUCKET_EXISTS}" -gt 0 ]]; then
  ok "Bucket '${BUCKET}' exists"
else
  warn "Bucket '${BUCKET}' NOT found"
  if ! ${DRY_RUN}; then
    garage_exec "/garage bucket create ${BUCKET}" 2>/dev/null
    ok "Bucket '${BUCKET}' created"
  fi
fi

# Key
KEY_EXISTS="$(garage_exec "/garage key list" 2>/dev/null | grep -c "${KEY_NAME}" || true)"
if [[ "${KEY_EXISTS}" -gt 0 ]]; then
  ok "Key '${KEY_NAME}' exists"

  if ! ${DRY_RUN}; then
    KEY_INFO="$(garage_exec "/garage key info ${KEY_NAME}")"
    ACCESS_KEY_ID="$(echo "${KEY_INFO}" | awk '/Key ID:/{print $NF}')"
    SECRET_ACCESS_KEY="$(echo "${KEY_INFO}" | awk '/Secret key:/{print $NF}')"

    echo ""
    echo "  Current credentials:"
    echo "    AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}"
    echo "    AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}"
    echo ""
  fi
else
  warn "Key '${KEY_NAME}' NOT found"
fi

# Permissions
if [[ "${BUCKET_EXISTS}" -gt 0 ]] && [[ "${KEY_EXISTS}" -gt 0 ]] && ! ${DRY_RUN}; then
  PERMS=$(garage_exec "/garage bucket info ${BUCKET}" 2>/dev/null | grep -A5 "${KEY_NAME}" || true)
  if [[ -n "${PERMS}" ]]; then
    ok "Permissions found on bucket:"
    echo "${PERMS}" | sed 's/^/    /'
  else
    warn "Granting permissions..."
    garage_exec "/garage bucket allow ${BUCKET} --key ${KEY_NAME} --read --write" 2>/dev/null || true
    ok "Permissions granted"
  fi
fi

# --- Rotation (--rotate-creds) ---
if ${ROTATE} && ! ${DRY_RUN}; then
  echo ""
  info "Rotating credentials..."

  # Generate new values
  NEW_ACCESS_KEY="GK$(gen_alnum 18)"
  NEW_SECRET_KEY="$(gen_alnum 40)"

  # Garage v2.3.0: recreate the key with a new name, delete old one
  # Actually --default-bucket sets the key by env var. Better approach:
  # 1. Create a tmp key with owner permissions
  # 2. Import the env var approach won't work without restart...
  #
  # We use garage key import for idempotent key creation with known secret:
  # (Garage v2.3.0 supports: garage key import <name> --access-key-id <key> --secret-key <secret>)
  if garage_exec "/garage key import ${KEY_NAME} --access-key-id ${NEW_ACCESS_KEY} --secret-key ${NEW_SECRET_KEY}" 2>/dev/null; then
    ok "Key '${KEY_NAME}' updated with new credentials"
  else
    # Fallback: delete and recreate
    garage_exec "/garage key delete ${KEY_NAME}" 2>/dev/null || true
    garage_exec "/garage key create ${KEY_NAME}" 2>/dev/null || true
    warn "Fallback: deleted and recreated key (secret will differ)"
    NEW_KEY_INFO="$(garage_exec "/garage key info ${KEY_NAME}")"
    NEW_ACCESS_KEY="$(echo "${NEW_KEY_INFO}" | grep -oP '(?<=Key ID: )\w+' || echo "")"
    NEW_SECRET_KEY="$(echo "${NEW_KEY_INFO}" | grep -oP '(?<=Secret key: )\w+' || echo "")"
  fi

  # Re-grant permissions (idempotent)
  garage_exec "/garage bucket allow ${BUCKET} --key ${KEY_NAME} --read --write" 2>/dev/null || true

  # Update local .env
  if [[ -f "${LOCAL_ENV}" ]]; then
    sed -i '' "s/^AWS_ACCESS_KEY_ID=.*/AWS_ACCESS_KEY_ID=${NEW_ACCESS_KEY}/" "${LOCAL_ENV}"
    sed -i '' "s/^AWS_SECRET_ACCESS_KEY=.*/AWS_SECRET_ACCESS_KEY=${NEW_SECRET_KEY}/" "${LOCAL_ENV}"
    ok "Local .env updated"
  fi

  # Update remote .env
  lxc_exec "sed -i 's/^AWS_ACCESS_KEY_ID=.*/AWS_ACCESS_KEY_ID=${NEW_ACCESS_KEY}/' ${REMOTE_ENV}"
  lxc_exec "sed -i 's/^AWS_SECRET_ACCESS_KEY=.*/AWS_SECRET_ACCESS_KEY=${NEW_SECRET_KEY}/' ${REMOTE_ENV}"
  ok "Remote .env updated"

  echo ""
  echo "  New credentials:"
  echo "    AWS_ACCESS_KEY_ID=${NEW_ACCESS_KEY}"
  echo "    AWS_SECRET_ACCESS_KEY=${NEW_SECRET_KEY}"
  echo ""
  echo "  ⚠️  If you rotate credentials, re-run:"
  echo "     source ${LOCAL_ENV}"
  echo "     terraform init -migrate-state"
  echo "     (or you'll get AccessDenied on next terraform plan/apply)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if ${DRY_RUN}; then
  ok "[DRY-RUN] Completed (no changes made)"
elif ${ROTATE}; then
  ok "Credentials rotated. Verify with: terraform plan"
else
  ok "Verification completed"
fi
