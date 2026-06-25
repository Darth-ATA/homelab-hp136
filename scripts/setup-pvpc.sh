#!/bin/bash
#===============================================================================
# Setup PVPC (Spain Electricity Pricing) on Home Assistant
#===============================================================================
# Installs ha-pvpc-next custom component + pvpc-hourly-pricing-card Lovelace
# card on the Home Assistant VM.
#
# Usage:
#   ./setup-pvpc.sh                    Full setup (component + card + restart + verify)
#   ./setup-pvpc.sh --component-only   Only install ha-pvpc-next
#   ./setup-pvpc.sh --card-only        Only install pvpc-hourly-pricing-card
#   ./setup-pvpc.sh --no-restart       Skip HA Core restart
#   ./setup-pvpc.sh --skip-verify      Skip sensor verification
#   ./setup-pvpc.sh --dry-run          Show what would be done
#
# Prerequisites:
#   - SSH key authentication configured for Proxmox host
#   - Home Assistant VM (100) must be running
#   - Home Assistant container must be running inside the VM
#
# Post-Setup (manual, HA storage mode):
#   1. Create config entry in Settings → Devices & Services → Add Integration
#      (or directly in .storage/core.config_entries)
#   2. Register card resource: Settings → Dashboards → Resources → Add Resource
#      URL: /local/community/pvpc-hourly-pricing-card/pvpc-hourly-pricing-card.js
#   3. Add card to dashboard via UI
#===============================================================================

set -Eeuo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
VM_ID="100"
PROXMOX_HOST="192.168.1.134"
SSH_KEY="$HOME/.ssh/homelab_key"
HA_CONTAINER="homeassistant"
TMPDIR_REMOTE="/tmp/pvpc-setup"

PVPC_NEXT_VERSION="2.2.2"
PVPC_NEXT_URL="https://github.com/privatecoder/ha-pvpc-next/archive/refs/tags/${PVPC_NEXT_VERSION}.tar.gz"

CARD_VERSION="3.0.0-next"
CARD_URL="https://github.com/privatecoder/pvpc-hourly-pricing-card/archive/refs/heads/master.tar.gz"

#-------------------------------------------------------------------------------
# Colors (matching repo style)
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# Logging (matching repo style)
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
Usage: $(basename "$0") [OPTIONS]

Install ha-pvpc-next (v${PVPC_NEXT_VERSION}) + pvpc-hourly-pricing-card (v${CARD_VERSION})
on Home Assistant VM ${VM_ID}.

Options:
  --component-only    Only install ha-pvpc-next component
  --card-only         Only install pvpc-hourly-pricing-card
  --no-restart        Skip HA Core restart after install
  --skip-verify       Skip sensor verification after restart
  --dry-run           Show what would be done without making changes
  -h, --help          Show this help message

Post-setup manual steps (HA storage mode):
  1. Create config entry via Settings → Devices & Services
  2. Register card resource via Settings → Dashboards → Resources
  3. Add card to dashboard via UI

See docs/pvpc-setup.md for details.
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

run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi
    "$@"
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

    # Docker container status
    if ! guest_exec docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${HA_CONTAINER}$"; then
        log_error "Container $HA_CONTAINER not found in VM $VM_ID"
        exit 1
    fi

    log_success "Prerequisites validated"
}

#-------------------------------------------------------------------------------
# ha-pvpc-next Component Install
#-------------------------------------------------------------------------------
install_component() {
    echo ""
    echo "=============================================="
    echo "  Installing ha-pvpc-next v${PVPC_NEXT_VERSION}"
    echo "=============================================="
    echo ""

    log_info "[1/4] Creating temp directory on Proxmox host..."
    run_cmd ssh_cmd mkdir -p "$TMPDIR_REMOTE"

    log_info "[2/4] Downloading ha-pvpc-next v${PVPC_NEXT_VERSION}..."
    run_cmd ssh_cmd "curl -sL '$PVPC_NEXT_URL' | tar xz -C '$TMPDIR_REMOTE'"

    log_info "[3/4] Copying custom_components to HA container..."
    run_cmd ssh_cmd "docker cp '${TMPDIR_REMOTE}/ha-pvpc-next-${PVPC_NEXT_VERSION}/custom_components/pvpc_next' \
        '${HA_CONTAINER}:/config/custom_components/pvpc_next/'" 2>/dev/null || {
        log_error "Failed to copy component to container"
        exit 1
    }

    log_info "[4/4] Verifying files in container..."
    local file_count
    file_count=$(guest_exec sh -c "ls -la /config/custom_components/pvpc_next/*.py 2>/dev/null | wc -l" 2>/dev/null) || file_count=0
    if [[ "$file_count" -gt 0 ]]; then
        log_success "Component installed: $file_count Python files"
    else
        log_error "No files found in /config/custom_components/pvpc_next/"
        exit 1
    fi

    log_success "ha-pvpc-next v${PVPC_NEXT_VERSION} installed"
}

#-------------------------------------------------------------------------------
# pvpc-hourly-pricing-card Install
#-------------------------------------------------------------------------------
install_card() {
    echo ""
    echo "=============================================="
    echo "  Installing pvpc-hourly-pricing-card v${CARD_VERSION}"
    echo "=============================================="
    echo ""

    log_info "[1/4] Creating temp directory on Proxmox host..."
    run_cmd ssh_cmd mkdir -p "$TMPDIR_REMOTE"

    log_info "[2/4] Downloading card v${CARD_VERSION}..."
    run_cmd ssh_cmd "curl -sL '$CARD_URL' | tar xz -C '$TMPDIR_REMOTE'"

    log_info "[3/4] Creating target directory in container..."
    run_cmd guest_exec sh -c "mkdir -p /config/www/community/pvpc-hourly-pricing-card" 2>/dev/null || true

    log_info "[4/4] Copying card JS to container..."
    run_cmd ssh_cmd "docker cp '${TMPDIR_REMOTE}/pvpc-hourly-pricing-card-master/dist/pvpc-hourly-pricing-card.js' \
        '${HA_CONTAINER}:/config/www/community/pvpc-hourly-pricing-card/'" 2>/dev/null || {
        log_error "Failed to copy card to container"
        exit 1
    }

    local file_size
    file_size=$(guest_exec sh -c "stat -c%s /config/www/community/pvpc-hourly-pricing-card/pvpc-hourly-pricing-card.js 2>/dev/null || echo 0" 2>/dev/null)
    if [[ "$file_size" -gt 0 ]]; then
        log_success "Card installed: $(numfmt --to=iec "$file_size")"
    else
        log_warn "Could not verify card file size"
    fi

    log_success "pvpc-hourly-pricing-card v${CARD_VERSION} installed"
    echo ""
    log_warn "Resource must be registered via UI:"
    log_warn "  Settings → Dashboards → Resources → Add Resource"
    log_warn "  URL: /local/community/pvpc-hourly-pricing-card/pvpc-hourly-pricing-card.js"
}

#-------------------------------------------------------------------------------
# HA Restart
#-------------------------------------------------------------------------------
restart_ha() {
    if [[ "${SKIP_RESTART:-false}" == "true" ]]; then
        log_warn "Skipping HA Core restart (--no-restart flag)"
        log_info "Restart manually: Settings → System → Restart"
        return
    fi

    echo ""
    echo "=============================================="
    echo "  Restarting Home Assistant"
    echo "=============================================="
    echo ""

    log_info "Triggering HA Core restart..."
    guest_exec ha core restart 2>/dev/null || {
        log_warn "ha core restart failed, trying supervisor restart..."
        guest_exec ha supervisor restart 2>/dev/null || true
    }

    log_info "Waiting 30s for HA to come back..."
    sleep 30

    log_success "HA restart triggered"
}

#-------------------------------------------------------------------------------
# Verification
#-------------------------------------------------------------------------------
verify() {
    if [[ "${SKIP_VERIFY:-false}" == "true" ]]; then
        log_warn "Skipping sensor verification"
        return
    fi

    echo ""
    echo "=============================================="
    echo "  Verifying PVPC Sensors"
    echo "=============================================="
    echo ""

    log_info "Checking sensor.esios_current_price via supervisor socket..."

    local result
    result=$(guest_exec sh -c "curl -s --unix-socket /run/supervisor/core.sock \
        http://supervisor/api/states/sensor.esios_current_price 2>/dev/null" 2>/dev/null || echo "")

    if [[ -z "$result" ]]; then
        log_warn "Sensor not available yet (HA may still be starting)"
        log_info "Try again in a minute:"
        log_info "  docker exec homeassistant sh -c \\"
        log_info "    'curl -s --unix-socket /run/supervisor/core.sock \\"
        log_info "      http://supervisor/api/states/sensor.esios_current_price'"
        return
    fi

    local state
    state=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','unknown'))" 2>/dev/null || echo "unknown")

    if [[ "$state" != "unknown" ]] && [[ "$state" != "unavailable" ]]; then
        log_success "Sensor sensor.esios_current_price = $state €/kWh"
    elif [[ "$state" == "unavailable" ]]; then
        log_warn "Sensor exists but is unavailable (no data from ESIOS)"
        log_info "Force refresh:"
        log_info "  docker exec homeassistant sh -c \\"
        log_info "    'curl -s -X POST --unix-socket /run/supervisor/core.sock \\"
        log_info "      http://supervisor/api/services/pvpc_next/update'"
    else
        log_warn "Sensor state: $state"
    fi

    # Count PVPC entities
    log_info "Counting registered PVPC entities..."
    local entity_count
    entity_count=$(guest_exec sh -c "curl -s --unix-socket /run/supervisor/core.sock \
        http://supervisor/api/states 2>/dev/null | python3 -c \
        \"import sys,json; data=json.load(sys.stdin); \
        print(len([e for e in (data if isinstance(data,list) else []) \
        if e['entity_id'].startswith('sensor.esios')]))\" 2>/dev/null" 2>/dev/null || echo "0")

    if [[ "$entity_count" -gt 0 ]]; then
        log_success "$entity_count PVPC sensors found"
    else
        log_warn "No PVPC sensors found. Config entry may not exist yet."
        log_info "Create it via: Settings → Devices & Services → Add Integration → PVPC Next"
    fi
}

#-------------------------------------------------------------------------------
# Cleanup
#-------------------------------------------------------------------------------
_cleaned_up=false
cleanup() {
    $_cleaned_up && return
    _cleaned_up=true

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        return
    fi

    log_info "Cleaning up temp files..."
    ssh_cmd "rm -rf '$TMPDIR_REMOTE'" 2>/dev/null || true
    log_success "Cleanup complete"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    local do_component=true
    local do_card=true
    SKIP_RESTART=false
    SKIP_VERIFY=false
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --component-only)
                do_card=false
                shift
                ;;
            --card-only)
                do_component=false
                shift
                ;;
            --no-restart)
                SKIP_RESTART=true
                shift
                ;;
            --skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage 1
                ;;
        esac
    done

    echo ""
    echo "=============================================="
    echo "  PVPC Setup Script"
    echo "  Target:     VM $VM_ID @ $PROXMOX_HOST"
    echo "  Component:  ha-pvpc-next v${PVPC_NEXT_VERSION}"
    echo "  Card:       pvpc-hourly-pricing-card v${CARD_VERSION}"
    echo "  Dry-run:    ${DRY_RUN}"
    echo "=============================================="
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN mode — no changes will be made"
        echo ""
    fi

    trap cleanup EXIT

    validate_prerequisites

    if [[ "$do_component" == "true" ]]; then
        install_component
    fi

    if [[ "$do_card" == "true" ]]; then
        install_card
    fi

    restart_ha
    verify

    echo ""
    echo "=============================================="
    echo "  Setup Complete!"
    echo "=============================================="
    echo ""
    log_info "Remaining manual steps (HA storage mode):"
    echo ""
    log_info "1. Create config entry:"
    log_info "   Settings → Devices & Services → Add Integration"
    log_info "   Search 'PVPC Next' → Configure (tariff: 2.0TD, power: 3450W)"
    echo ""
    log_info "2. Register card resource:"
    log_info "   Settings → Dashboards → Resources → Add Resource"
    log_info "   URL: /local/community/pvpc-hourly-pricing-card/pvpc-hourly-pricing-card.js"
    echo ""
    log_info "3. Add card to dashboard:"
    log_info "   Edit dashboard → Add Card → Custom: PVPC Hourly Pricing"
    echo ""
    log_info "See docs/pvpc-setup.md for full details and troubleshooting."
    echo ""
}

main "$@"
