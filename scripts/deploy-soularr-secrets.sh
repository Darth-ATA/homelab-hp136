#!/usr/bin/env bash
# Deploy Soularr + slskd secrets from local .env files to LXC 101
#
# Usage:
#   1. Copy .env.example to .env and fill in your secrets:
#      cp docker/slskd/.env.example docker/slskd/.env
#      cp docker/soularr/.env.example docker/soularr/.env
#      # Edit both .env files with your actual secrets
#
#   2. Run this script:
#      ./scripts/deploy-soularr-secrets.sh
#
# This script reads your local .env files and injects them
# into the config files on LXC 101 via SSH. Your secrets
# never go through the AI chat.

set -euo pipefail

PROXMOX_HOST="192.168.1.134"
SSH_KEY="$HOME/.ssh/homelab_key"
SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no root@${PROXMOX_HOST}"
LXC="101"

# --- Load secrets ---
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SLSKD_ENV="${SCRIPT_DIR}/docker/slskd/.env"
SOULARR_ENV="${SCRIPT_DIR}/docker/soularr/.env"

if [ ! -f "$SLSKD_ENV" ]; then
  echo "ERROR: $SLSKD_ENV not found. Run: cp docker/slskd/.env.example docker/slskd/.env"
  exit 1
fi

if [ ! -f "$SOULARR_ENV" ]; then
  echo "ERROR: $SOULARR_ENV not found. Run: cp docker/soularr/.env.example docker/soularr/.env"
  exit 1
fi

# shellcheck disable=SC1090
source "$SLSKD_ENV"
# shellcheck disable=SC1090
source "$SOULARR_ENV"

# --- Validate ---
if [ "${SOULSEEK_USER:-}" = "your_soulseek_username" ] || [ -z "${SOULSEEK_USER:-}" ]; then
  echo "ERROR: Set SOULSEEK_USER in $SLSKD_ENV"
  exit 1
fi
if [ "${SOULSEEK_PASS:-}" = "your_soulseek_password" ] || [ -z "${SOULSEEK_PASS:-}" ]; then
  echo "ERROR: Set SOULSEEK_PASS in $SLSKD_ENV"
  exit 1
fi
if [ "${LIDARR_API_KEY:-}" = "your_lidarr_api_key_here" ] || [ -z "${LIDARR_API_KEY:-}" ]; then
  echo "ERROR: Set LIDARR_API_KEY in $SOULARR_ENV"
  exit 1
fi

echo "✓ Secrets loaded"
echo "  SOULSEEK_USER: ${SOULSEEK_USER}"
echo "  LIDARR_API_KEY: ${LIDARR_API_KEY:0:8}..."
echo ""

# --- Inject slskd.yml (Soulseek credentials) ---
echo "→ Injecting Soulseek credentials into slskd.yml..."
${SSH_CMD} "pct exec ${LXC} -- sed -i 's|\"SOULSEEK_USER_GOES_HERE\"|\"${SOULSEEK_USER}\"|' /root/docker/slskd/config/slskd.yml"
${SSH_CMD} "pct exec ${LXC} -- sed -i 's|\"SOULSEEK_PASS_GOES_HERE\"|\"${SOULSEEK_PASS}\"|' /root/docker/slskd/config/slskd.yml"
echo "✓ slskd.yml updated"

# --- Inject config.ini (Lidarr API key) ---
echo "→ Injecting Lidarr API key into config.ini..."
${SSH_CMD} "pct exec ${LXC} -- sed -i 's/LIDARR_API_KEY_GOES_HERE/${LIDARR_API_KEY}/' /root/docker/soularr/config/config.ini"
echo "✓ config.ini updated"

# --- Restart containers ---
echo "→ Restarting containers..."
${SSH_CMD} "pct exec ${LXC} -- docker restart slskd soularr"
echo "✓ Containers restarted"

echo ""
echo "✅ Done! Secrets deployed and containers restarted."
echo "   slskd web UI:  http://192.168.1.142:5030"
echo "   soularr web UI: http://192.168.1.142:8265"
echo ""
echo "   Check logs:"
echo "   ssh -i ~/.ssh/homelab_key root@${PROXMOX_HOST} \"pct exec ${LXC} -- docker logs slskd --tail 30\""
echo "   ssh -i ~/.ssh/homelab_key root@${PROXMOX_HOST} \"pct exec ${LXC} -- docker logs soularr --tail 30\""
