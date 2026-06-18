#!/bin/bash
# *arr Root Folder Setup Script
# Adds/updates root folders in Radarr, Sonarr, and Lidarr after fresh deploy.
# Also updates existing series/movies/artists if their path uses old mounts.
#
# Usage:
#   ./setup-arr-paths.sh                  # Run locally (inside LXC 101)
#   ./setup-arr-paths.sh --lxc 101        # Run via pct exec on Proxmox host
#   ./setup-arr-paths.sh --dry-run        # Preview only, no changes
#
# Prerequisites: Services must be running and accessible on localhost.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

DRY_RUN="${DRY_RUN:-false}"

# Root folder paths (with /data:/data single mount)
declare -A ROOT_FOLDERS
ROOT_FOLDERS[radarr]="/data/media/movies"
ROOT_FOLDERS[sonarr]="/data/media/tv"
ROOT_FOLDERS[lidarr]="/data/media/music"

# Old mount paths to migrate from (key = service, value = old prefix)
declare -A OLD_PATHS
OLD_PATHS[radarr]="/movies"
OLD_PATHS[sonarr]="/tv"
OLD_PATHS[lidarr]="/music"

# Service config & ports
declare -A PORTS
PORTS[radarr]="7878"
PORTS[sonarr]="8989"
PORTS[lidarr]="8686"

# Config directories inside LXC
CONFIG_DIR="/root/docker"

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

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

get_api_key() {
  local service="$1"
  local config_file="$CONFIG_DIR/$service/config/config.xml"

  if [[ ! -f "$config_file" ]]; then
    log_error "Config not found: $config_file"
    return 1
  fi

  # Extract ApiKey from config.xml
  grep -oP '(?<=<ApiKey>)[^<]+' "$config_file" 2>/dev/null || return 1
}

api_get() {
  local service="$1" endpoint="$2"
  local api_key port
  api_key=$(get_api_key "$service") || return 1
  port="${PORTS[$service]}"

  curl -sf "http://localhost:$port/api/v1$endpoint" \
    -H "X-Api-Key: $api_key" 2>/dev/null || return 1
}

api_post() {
  local service="$1" endpoint="$2" data="$3"
  local api_key port
  api_key=$(get_api_key "$service") || return 1
  port="${PORTS[$service]}"

  curl -sf -X POST "http://localhost:$port/api/v1$endpoint" \
    -H "X-Api-Key: $api_key" \
    -H "Content-Type: application/json" \
    -d "$data" 2>/dev/null || return 1
}

api_put() {
  local service="$1" endpoint="$2" data="$3"
  local api_key port
  api_key=$(get_api_key "$service") || return 1
  port="${PORTS[$service]}"

  curl -sf -X PUT "http://localhost:$port/api/v1$endpoint" \
    -H "X-Api-Key: $api_key" \
    -H "Content-Type: application/json" \
    -d "$data" 2>/dev/null || return 1
}

# ---------------------------------------------------------------------------
# Per-service setup
# ---------------------------------------------------------------------------

setup_root_folder() {
  local service="$1"
  local path="${ROOT_FOLDERS[$service]}"

  log_info "  Adding root folder: $path"

  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi

  # Check if already exists
  local existing
  existing=$(api_get "$service" "/rootFolder" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for rf in data:
    if rf.get('path') == '$path':
        print(rf['id'])
" 2>/dev/null)

  if [[ -n "$existing" ]]; then
    log_info "  Root folder already exists (id=$existing) — skipping"
    return 0
  fi

  # Create root folder
  local result
  result=$(api_post "$service" "/rootFolder" "{\"path\": \"$path\"}") || {
    log_warn "  Failed to create root folder (service may not be ready)"
    return 1
  }

  local new_id
  new_id=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "?")
  log_info "  Root folder created (id=$new_id) ✓"
}

migrate_existing_items() {
  local service="$1"
  local endpoint=""
  local id_field=""
  local resource=""

  case "$service" in
    radarr)
      endpoint="movie"
      resource="movies"
      id_field="tmdbId"
      ;;
    sonarr)
      endpoint="series"
      resource="series"
      id_field="tvdbId"
      ;;
    lidarr)
      endpoint="artist"
      resource="artists"
      id_field=""
      ;;
    *)
      log_error "Unknown service: $service"
      return 1
      ;;
  esac

  local old_prefix="${OLD_PATHS[$service]}"
  local new_prefix="${ROOT_FOLDERS[$service]}"
  local count=0

  log_info "  Checking $resource for path migration..."

  local items
  items=$(api_get "$service" "/$endpoint" 2>/dev/null) || {
    log_info "  No $resource found or service not ready — skipping"
    return 0
  }

  # Process each item with Python
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "$items" | python3 -c "
import sys, json
data = json.load(sys.stdin)
old = '$old_prefix'
new = '$new_prefix'
for item in data:
    p = item.get('path', '')
    rfp = item.get('rootFolderPath', '')
    if p.startswith(old + '/') or rfp == old:
        name = item.get('title') or item.get('artistName') or item.get('seriesName', '?')
        print(f'    Would migrate: {name} → {new}')
" 2>/dev/null
    return 0
  fi

  # For each item with old paths, update them
  echo "$items" | python3 -c "
import sys, json, urllib.request

data = json.load(sys.stdin)
service = '$service'
old = '$old_prefix'
new = '$new_prefix'
port = '${PORTS[$service]}'
api_key = open('$CONFIG_DIR/$service/config/config.xml').read().split('<ApiKey>')[1].split('</ApiKey>')[0]
endpoint = '$endpoint'

updated = 0
for item in data:
    p = item.get('path', '')
    rfp = item.get('rootFolderPath', '')
    needs_update = False

    if p.startswith(old + '/'):
        item['path'] = p.replace(old, new, 1)
        needs_update = True

    if rfp == old:
        item['rootFolderPath'] = new
        needs_update = True

    if needs_update:
        name = item.get('title') or item.get('artistName') or item.get('seriesName', '?')
        item_id = item.get('id')
        req = urllib.request.Request(f'http://localhost:{port}/api/v1/{endpoint}/{item_id}')
        req.add_header('X-Api-Key', api_key)
        req.add_header('Content-Type', 'application/json')
        req.data = json.dumps(item).encode()
        req.method = 'PUT'
        try:
            with urllib.request.urlopen(req) as resp:
                print(f'  ✓ {name}')
                updated += 1
        except Exception as e:
            print(f'  ✗ {name}: {e}')

print(f'  Migrated: {updated}')
sys.exit(0 if True else 1)
" 2>/dev/null || log_warn "  Migration encountered errors"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --lxc)
        local lxc_id="$2"
        shift 2
        # Re-execute inside LXC
        exec ssh -i "$HOME/.ssh/homelab_key" root@192.168.1.134 \
          "pct exec $lxc_id -- bash -c '$(cat "$0")'" 2>/dev/null || {
          log_error "Failed to run inside LXC. Make sure Proxmox is reachable."
          exit 1
        }
        ;;
      *)
        log_error "Unknown option: $1"
        echo "Usage: $0 [--dry-run] [--lxc ID]" >&2
        exit 1
        ;;
    esac
  done

  # Verify we're inside the LXC (or have direct access)
  if ! command -v docker &>/dev/null && [[ -z "${LXC_EXEC:-}" ]]; then
    log_warn "Not inside LXC — use --lxc 101 to run via Proxmox"
    exit 1
  fi

  echo "=== *arr Root Folder Setup ==="
  echo ""

  for service in radarr sonarr lidarr; do
    echo "--- $service (port ${PORTS[$service]}) ---"

    if ! get_api_key "$service" &>/dev/null; then
      log_warn "  Config not found — skipping (not deployed?)"
      echo ""
      continue
    fi

    setup_root_folder "$service"
    migrate_existing_items "$service"
    echo ""
  done

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "=== DRY RUN — no changes made ==="
  else
    echo "=== Done ==="
  fi
}

main "$@"
