#!/bin/bash
#===============================================================================
# Deploy HA Config to Home Assistant VM
#===============================================================================
# Deploys YAML configuration files (automations.yaml, scripts.yaml, etc.) from
# the local ha-config/ directory to the Home Assistant OS VM via Proxmox guest
# agent + temporary HTTP server.
#
# Usage:
#   ./deploy-ha-config.sh                    Deploy default files (automations, scripts)
#   ./deploy-ha-config.sh --all              Deploy all YAML files except config
#   ./deploy-ha-config.sh scenes.yaml        Deploy specific file(s)
#   ./deploy-ha-config.sh --list             List available config files
#   ./deploy-ha-config.sh --no-restart       Skip HA Core restart
#
# Prerequisites:
#   - SSH key authentication configured for Proxmox host
#   - Home Assistant VM (100) must be running
#   - QEMU guest agent must be running inside the VM
#===============================================================================

set -Eeuo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
VM_ID="100"
PROXMOX_HOST="192.168.1.134"
SSH_KEY="$HOME/.ssh/homelab_key"
LOCAL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../ha-config" && pwd -P)"
REMOTE_DIR="/mnt/data/supervisor/homeassistant"
HTTP_PORT="8000"
DEFAULT_FILES=("automations.yaml" "scripts.yaml")

#-------------------------------------------------------------------------------
# Colors
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# Logging
#-------------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

#-------------------------------------------------------------------------------
# Help
#-------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [FILE...]

Deploy HA YAML config files from ha-config/ to the Home Assistant VM.

Options:
  --all             Deploy all .yaml files (except configuration.yaml)
  --list            List available config files and exit
  --no-restart      Skip HA Core restart after deploy
  -h, --help        Show this help message

Files:
  If no files are specified, deploys: ${DEFAULT_FILES[*]}

Examples:
  ./deploy-ha-config.sh
  ./deploy-ha-config.sh --all
  ./deploy-ha-config.sh automations.yaml scenes.yaml
  ./deploy-ha-config.sh --no-restart scripts.yaml
EOF
    exit "${1:-0}"
}

#-------------------------------------------------------------------------------
# Helpers
#-------------------------------------------------------------------------------
ssh_cmd() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "root@${PROXMOX_HOST}" -- "$@"
}

guest_exec() {
    ssh_cmd qm guest exec "$VM_ID" -- "$@"
}

#-------------------------------------------------------------------------------
# Validation
#-------------------------------------------------------------------------------
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # SSH key
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key not found: $SSH_KEY"
        exit 1
    fi

    # Local directory
    if [[ ! -d "$LOCAL_DIR" ]]; then
        log_error "HA config directory not found: $LOCAL_DIR"
        exit 1
    fi

    # SSH connectivity
    if ! ssh_cmd true 2>/dev/null; then
        log_error "Cannot connect to Proxmox host $PROXMOX_HOST"
        exit 1
    fi

    # VM status
    local vm_status
    vm_status=$(ssh_cmd qm status "$VM_ID" 2>/dev/null | awk '{print $2}') || {
        log_error "Cannot check VM $VM_ID status"
        exit 1
    }
    if [[ "$vm_status" != "running" ]]; then
        log_error "VM $VM_ID is not running (status: $vm_status)"
        exit 1
    fi

    # Guest agent
    if ! ssh_cmd qm agent "$VM_ID" ping &>/dev/null; then
        log_error "QEMU guest agent not responding on VM $VM_ID"
        exit 1
    fi

    log_success "Prerequisites validated"
}

#-------------------------------------------------------------------------------
# File Selection
#-------------------------------------------------------------------------------
list_files() {
    echo "Available config files in $LOCAL_DIR:"
    echo ""
    for f in "$LOCAL_DIR"/*.yaml; do
        local name
        name=$(basename "$f")
        local is_default=false
        for df in "${DEFAULT_FILES[@]}"; do
            [[ "$name" == "$df" ]] && { is_default=true; break; }
        done

        if [[ "$name" == "configuration.yaml" ]]; then
            echo "  $name  (SKIPPED by default)"
        elif [[ "$is_default" == "true" ]]; then
            echo "  $name  (default)"
        else
            echo "  $name"
        fi
    done
    echo ""
    echo "Default deploy: ${DEFAULT_FILES[*]}"
    echo "Deploy all:     --all flag"
}

resolve_files() {
    local -a files=()

    if [[ "${DEPLOY_ALL:-false}" == "true" ]]; then
        for f in "$LOCAL_DIR"/*.yaml; do
            local name
            name=$(basename "$f")
            [[ "$name" != "configuration.yaml" ]] && files+=("$name")
        done
    elif [[ $# -gt 0 ]]; then
        files=("$@")
    else
        files=("${DEFAULT_FILES[@]}")
    fi

    local -a resolved=()
    for f in "${files[@]}"; do
        if [[ ! -f "$LOCAL_DIR/$f" ]]; then
            log_warn "File not found, skipping: $f"
            continue
        fi
        resolved+=("$f")
    done

    if [[ ${#resolved[@]} -eq 0 ]]; then
        log_error "No valid files to deploy"
        exit 1
    fi

    printf '%s\n' "${resolved[@]}"
}

#-------------------------------------------------------------------------------
# Deploy
#-------------------------------------------------------------------------------
copy_to_proxmox() {
    local -a files=("$@")
    log_info "[1/4] Copying ${#files[@]} file(s) to Proxmox host..."

    ssh_cmd mkdir -p /tmp/ha-deploy

    for f in "${files[@]}"; do
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -q \
            "$LOCAL_DIR/$f" "root@${PROXMOX_HOST}:/tmp/ha-deploy/$f"
        log_success "Copied $f"
    done
}

start_http_server() {
    log_info "[2/4] Starting temporary HTTP server on Proxmox host..."

    ssh_cmd "nohup python3 -m http.server $HTTP_PORT -d /tmp/ha-deploy \
        >/dev/null 2>&1 & echo \$!"

    sleep 1

    if ! guest_exec curl -s -o /dev/null -w '%{http_code}' \
        "http://${PROXMOX_HOST}:${HTTP_PORT}/" 2>/dev/null | grep -q 200; then
        log_error "HTTP server not responding on port $HTTP_PORT"
        cleanup
        exit 1
    fi

    log_success "HTTP server running on ${PROXMOX_HOST}:${HTTP_PORT}"
}

push_files_to_vm() {
    local -a files=("$@")
    log_info "[3/4] Pushing ${#files[@]} file(s) to VM $VM_ID..."

    for f in "${files[@]}"; do
        local url="http://${PROXMOX_HOST}:${HTTP_PORT}/$f"
        local size
        size=$(curl -sI "$url" 2>/dev/null | grep -i content-length | awk '{print $2}' | tr -d '\r' || echo "0")

        if ! guest_exec curl -s -o "${REMOTE_DIR}/${f}" "$url" >/dev/null 2>&1; then
            log_error "Failed to push $f"
            cleanup
            exit 1
        fi

        log_success "Pushed $f (${size:-0} bytes)"
    done
}

restart_ha() {
    if [[ "${SKIP_RESTART:-false}" == "true" ]]; then
        log_warn "Skipping HA Core restart (--no-restart flag)"
        log_info "Reload manually: Settings → System → Restart"
        return
    fi

    log_info "Restarting Home Assistant Core..."
    guest_exec ha core restart 2>/dev/null || {
        log_warn "ha core restart failed, trying supervisor restart..."
        guest_exec ha supervisor restart 2>/dev/null || true
    }
    log_success "HA Core restart triggered"
}

_cleaned_up=false
cleanup() {
    $_cleaned_up && return
    _cleaned_up=true
    log_info "Cleaning up..."
    ssh_cmd "pkill -f 'python3 -m http.server ${HTTP_PORT}' 2>/dev/null || true"
    ssh_cmd "rm -rf /tmp/ha-deploy" 2>/dev/null || true
    log_success "Cleanup complete"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    local -a deploy_files=()
    SKIP_RESTART=false
    DEPLOY_ALL=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                DEPLOY_ALL=true
                shift
                ;;
            --list)
                list_files
                exit 0
                ;;
            --no-restart)
                SKIP_RESTART=true
                shift
                ;;
            -h|--help)
                usage 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage 1
                ;;
            *)
                deploy_files+=("$1")
                shift
                ;;
        esac
    done

    echo ""
    echo "=============================================="
    echo "  HA Config Deploy Script"
    echo "  Target: VM $VM_ID @ $PROXMOX_HOST"
    echo "  Path:   $REMOTE_DIR"
    echo "=============================================="
    echo ""

    validate_prerequisites

    local -a files=()
    while IFS= read -r line; do
        files+=("$line")
    done < <(resolve_files "${deploy_files[@]}")
    echo "Deploying: ${files[*]}"
    echo ""

    trap cleanup EXIT

    copy_to_proxmox "${files[@]}"
    start_http_server
    push_files_to_vm "${files[@]}"

    echo ""
    log_success "All files deployed to VM $VM_ID"
    echo ""

    restart_ha

    echo ""
    echo "=============================================="
    echo "  Deploy Complete!"
    echo "=============================================="
    echo ""
    log_info "Changes take effect after HA Core restart (~30-60s)"
    echo ""
}

main "$@"
