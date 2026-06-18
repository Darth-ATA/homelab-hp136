#!/bin/bash
# Media Stack Deployment Script
# Deploys Docker media stack (arr apps, Prowlarr, Jellyfin, Deluge, etc.)
# to LXC 101 from the compose files in docker/
#
# Usage: ./deploy-media-stack.sh [--dry-run]
#
# Idempotent: safe to re-run. Skips existing mounts, configs, and services.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

LXC_IP="192.168.1.142"
LXC_ID="101"
PROXMOX_IP="192.168.1.134"
SSH_KEY="$HOME/.ssh/homelab_key"
SSH_CMD="ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$PROXMOX_IP"
LXC_EXEC="$SSH_CMD pct exec $LXC_ID --"

# Which compose files to deploy (relative to docker/ dir)
SERVICES=(
  "npm"
  "vaultwarden"
  "deluge"
  "prowlarr"
  "radarr"
  "sonarr"
  "lidarr"
  "jellyfin"
  "bazarr"
)

DRY_RUN="${DRY_RUN:-false}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_info()  { echo "[$(date +'%H:%M:%S')] INFO:  $*" >&2; }
log_warn()  { echo "[$(date +'%H:%M:%S')] WARN:  $*" >&2; }
log_error() { echo "[$(date +'%H:%M:%S')] ERROR: $*" >&2; }

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] $*" >&2
    return 0
  fi
  "$@"
}

ssh_host() {
  run_cmd $SSH_CMD "$@"
}

pct_exec() {
  run_cmd $SSH_CMD "pct exec $LXC_ID -- $*"
}

pct_push() {
  local src="$1" dst="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] pct push $LXC_ID $src $dst" >&2
    return 0
  fi
  $SSH_CMD "pct push $LXC_ID '$src' '$dst'"
}

check_deps() {
  local missing=()
  for cmd in ssh scp; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing dependencies: ${missing[*]}"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

phase_storage() {
  log_info "Setting up storage directories on Proxmox host"

  ssh_host mkdir -p /data/{torrents,media}/{movies,tv,music}
  ssh_host chmod 777 -R /data

  log_info "Storage directories created at /data/"
}

phase_bind_mount() {
  local conf_file="/etc/pve/lxc/${LXC_ID}.conf"

  log_info "Configuring LXC bind mount"

  if ssh_host grep -q "mp0:.*mp=/data" "$conf_file" 2>/dev/null; then
    log_info "Bind mount already configured — skipping"
  else
    log_warn "Adding mp0 bind mount to $conf_file"
    ssh_host "echo 'mp0: /data,mp=/data' >> '$conf_file'"
    log_info "Restarting LXC $LXC_ID to apply mount..."
    ssh_host pct restart "$LXC_ID"
    log_info "Waiting for LXC to come back..."
    sleep 10
  fi

  # Verify mount
  if ! pct_exec ls -la /data/torrents &>/dev/null; then
    log_error "Mount /data not visible inside LXC — check LXC config"
    exit 1
  fi
  log_info "Mount verified inside LXC ✓"
}

phase_tun_device() {
  local conf_file="/etc/pve/lxc/${LXC_ID}.conf"

  log_info "Setting up TUN device for VPN"

  if ssh_host grep -q "/dev/net/tun" "$conf_file" 2>/dev/null; then
    log_info "TUN device already configured — skipping"
    return 0
  fi

  log_warn "Adding TUN device passthrough to $conf_file"
  ssh_host "echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> '$conf_file'"
  ssh_host "echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> '$conf_file'"

  if [[ "$DRY_RUN" != "true" ]]; then
    ssh_host pct stop "$LXC_ID"
    sleep 3
    ssh_host pct start "$LXC_ID"
    sleep 5
  fi

  # Verify
  if ! pct_exec ls -l /dev/net/tun &>/dev/null; then
    log_error "TUN device not available — check LXC config manually"
    exit 1
  fi
  log_info "TUN device verified ✓"
}

phase_deploy_compose() {
  log_info "Deploying compose files to LXC"

  # Ensure target directories exist inside LXC
  for service in "${SERVICES[@]}"; do
    pct_exec mkdir -p "/root/docker/$service"
  done

  # For each service, push compose file and extra files
  for service in "${SERVICES[@]}"; do
    local src_dir="$REPO_DIR/docker/$service"
    local dst_base="/root/docker/$service"

    if [[ ! -d "$src_dir" ]]; then
      log_warn "Source directory not found: $src_dir — skipping"
      continue
    fi

    # Push compose.yml
    if [[ -f "$src_dir/compose.yml" ]]; then
      pct_push "$src_dir/compose.yml" "$dst_base/compose.yml"
      log_info "  → $service/compose.yml"
    fi

    # Push env example if exists
    if [[ -f "$src_dir/.env.example" ]]; then
      pct_push "$src_dir/.env.example" "$dst_base/.env.example"
      log_info "  → $service/.env.example"
    fi

    # Push custom config dirs if they exist
    for extra in custom custom-cont-init.d config recovery.sh run_api.sh; do
      if [[ -e "$src_dir/$extra" ]]; then
        $SSH_CMD "pct push $LXC_ID '$src_dir/$extra' '$dst_base/$extra' 2>/dev/null || \
                   pct exec $LXC_ID -- mkdir -p '$dst_base/$extra'"
      fi
    done
  done

  # Push root .env.example if exists
  if [[ -f "$REPO_DIR/docker/.env.example" ]]; then
    pct_push "$REPO_DIR/docker/.env.example" "/root/docker/.env.example"
  fi

  log_info "Compose files deployed ✓"
}

phase_start_services() {
  log_info "Starting services (this may take a while)..."

  for service in "${SERVICES[@]}"; do
    local compose_dir="/root/docker/$service"

    if pct_exec test -f "$compose_dir/compose.yml"; then
      log_info "  Starting $service..."
      pct_exec bash -c "cd '$compose_dir' && docker compose up -d 2>/dev/null" || \
        log_warn "  $service failed to start (may need .env config)"
    else
      log_warn "  No compose.yml for $service — skipping"
    fi
  done

  log_info "Services started. Verify with: pct exec $LXC_ID -- docker ps"
}

phase_show_summary() {
  cat >&2 <<EOF

=== DEPLOYMENT SUMMARY ===

Storage:     /data/ (host) → /data/ (LXC 101)
Services:    ${#SERVICES[@]} compose files deployed

NEXT STEPS:
1. Configure VPN credentials:
   cp /root/docker/.env.example /root/docker/.env
   # Edit .env with your ProtonVPN credentials

2. Restart services that need VPN:
   pct exec $LXC_ID -- docker compose -f /root/docker/deluge/compose.yml up -d

3. Configure *arr root folders (if fresh install):
   Radarr → /data/media/movies
   Sonarr → /data/media/tv
   Lidarr → /data/media/music

4. Verify services:
   pct exec $LXC_ID -- docker ps
   curl -s http://$LXC_IP:7878  # Radarr
   curl -s http://$LXC_IP:8989  # Sonarr

IMPORTANT — Hardlinks:
  *arr containers mount /data:/data (single mount).
  Do NOT use separate mounts like /data/media/movies:/movies.
  Separate mounts break hardlinks with "Cross-device link" (EXDEV).

  Root folder paths (set in *arr UI or API):
    Radarr: /data/media/movies
    Sonarr: /data/media/tv
    Lidarr: /data/media/music

SERVICE URLs:
  Prowlarr:   http://$LXC_IP:9696
  Radarr:     http://$LXC_IP:7878
  Sonarr:     http://$LXC_IP:8989
  Lidarr:     http://$LXC_IP:8686
  Jellyfin:   http://$LXC_IP:8096
  Deluge:     http://$LXC_IP:8112
  Bazarr:     http://$LXC_IP:6767
  NPM:        http://$LXC_IP:81

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  # Parse --dry-run
  if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "DRY RUN MODE — no changes will be made"
  fi

  check_deps

  echo "=== Media Stack Deployment ==="
  echo "Target: LXC $LXC_ID ($LXC_IP) on $PROXMOX_IP"
  echo ""

  phase_storage
  phase_bind_mount
  phase_tun_device
  phase_deploy_compose
  phase_start_services
  phase_show_summary
}

main "$@"
