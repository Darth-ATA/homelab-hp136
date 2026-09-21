#!/usr/bin/env bash
# Update DARTH-GAIN on homelab Docker host (LXC 101)
# Usage: ./scripts/update-darth-gain.sh

set -euo pipefail

PROXMOX_HOST="${PROXMOX_HOST:-192.168.1.134}"
SSH_KEY="${SSH_KEY:-~/.ssh/homelab_key}"
CONTAINER_ID=101
PROJECT_DIR="/root/DARTH-GAIN"

echo "🔄 Updating DARTH-GAIN on $PROXMOX_HOST (CT $CONTAINER_ID)..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'REMOTE_SCRIPT'
  pct exec 101 -- sh -c '
    cd /root/DARTH-GAIN &&
    echo "📥 Fetching latest changes..." &&
    git fetch origin &&
    BEFORE=$(git rev-parse HEAD) &&
    git pull origin main &&
    AFTER=$(git rev-parse HEAD) &&
    if [ "$BEFORE" = "$AFTER" ]; then
      echo "✅ Already up to date ($BEFORE)"
      exit 0
    fi &&
    echo "🔨 Building new image..." &&
    docker compose build --no-cache &&
    echo "🚀 Restarting container..." &&
    docker compose up -d &&
    echo "⏳ Waiting for healthcheck..." &&
    sleep 3 &&
    curl -sf http://localhost:8000/health | grep -q "ok" &&
    echo "✅ DARTH-GAIN updated successfully! ($BEFORE -> $AFTER)" &&
    git log --oneline -1
  '
REMOTE_SCRIPT

echo "🌐 Dashboard: https://darthgain.hp136.duckdns.org"