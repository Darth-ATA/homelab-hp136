#!/bin/bash
# Media Stack Deployment Script
# Usage: ./deploy-media-stack.sh

set -e

LXC_IP="192.168.1.142"
LXC_ID="101"
PROXMOX_IP="192.168.1.134"
SSH_KEY="~/.ssh/homelab_key"

echo "=== Media Stack Deployment ==="
echo ""

# Step 1: Set up folder structure on Proxmox host
echo "[1/5] Setting up folder structure on Proxmox host..."
ssh -i $SSH_KEY root@$PROXMOX_IP << 'EOF'
mkdir -p /mnt/media/{torrents,media}/{movies,tv,music}
chmod 777 -R /mnt/media
echo "Folder structure created at /mnt/media"
EOF

# Step 2: Mount storage to LXC
echo "[2/5] Configuring LXC bind mount..."
ssh -i $SSH_KEY root@$PROXMOX_IP "grep -q 'mp0:' /etc/pve/lxc/${LXC_ID}.conf || echo 'mp0: /mnt/media,mp=/data' >> /etc/pve/lxc/${LXC_ID}.conf"
ssh -i $SSH_KEY root@$PROXMOX_IP "pct restart $LXC_ID"
echo "Waiting for LXC to restart..."
sleep 10

# Step 3: Verify mount in LXC
echo "[3/5] Verifying mount in LXC..."
ssh -i $SSH_KEY root@$PROXMOX_IP "pct exec $LXC_ID -- ls -la /data"

# Step 4: Copy compose files to LXC
echo "[4/5] Copying compose files to LXC..."
scp -i $SSH_KEY -r docker/ root@$PROXMOX_IP:/tmp/media-stack/
ssh -i $SSH_KEY root@$PROXMOX_IP "pct push $LXC_ID /tmp/media-stack/docker-compose.yml /root/docker/docker-compose.yml"
ssh -i $SSH_KEY root@$PROXMOX_IP "pct push $LXC_ID /tmp/media-stack/.env.example /root/docker/.env.example"

# Step 5: Instructions for user
echo ""
echo "[5/5] Deployment files copied!"
echo ""
echo "=== NEXT STEPS ==="
echo "1. SSH into LXC: ssh -i $SSH_KEY root@$PROXMOX_IP 'pct enter $LXC_ID'"
echo "2. Navigate to docker: cd /root/docker"
echo "3. Copy and edit .env: cp .env.example .env && vi .env"
echo "4. Start the stack: docker compose -f docker-compose.yml up -d"
echo "5. Verify: docker ps"
echo ""
echo "=== Service URLs (after deployment) ==="
echo "qBittorrent: http://$LXC_IP:8080"
echo "Prowlarr: http://$LXC_IP:9696"
echo "Radarr: http://$LXC_IP:7878"
echo "Sonarr: http://$LXC_IP:8989"
echo "Jellyfin: http://$LXC_IP:8096"
