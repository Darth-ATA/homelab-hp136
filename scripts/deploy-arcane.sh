#!/bin/bash
#===============================================================================
# Deploy Arcane to Docker LXC
#===============================================================================
# Deploys the Arcane containerized application to a Proxmox Docker LXC using
# pct exec for container management and docker-compose for application deployment.
#
# Usage:
#   ./deploy-arcane.sh          Deploy Arcane
#   ./deploy-arcane.sh --redeploy  Force redeploy (removes existing container first)
#
# Prerequisites:
#   - SSH key authentication configured for Proxmox host
#   - LXC must be running
#   - Source files must exist in docker/arcane/
#===============================================================================

set -euo pipefail

# Configuration
LXC_ID="101"
PROXMOX_HOST="192.168.1.134"
SSH_KEY="~/.ssh/homelab_key"
LOCAL_DIR="$(cd "$(dirname "$0")/../docker/arcane" && pwd)"
REMOTE_DIR="/root/docker/arcane"
APP_PORT="3552"
APP_URL="http://192.168.1.142:${APP_PORT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --redeploy    Force redeploy (removes existing container first)"
    echo "  -h, --help    Show this help message"
    echo ""
    exit 0
}

#-------------------------------------------------------------------------------
# Validation
#-------------------------------------------------------------------------------
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check for SSH key
    if [[ ! -f "${SSH_KEY/~\\/}" ]]; then
        local expanded_key="${SSH_KEY/\~/$HOME}"
        if [[ ! -f "$expanded_key" ]]; then
            log_error "SSH key not found: $SSH_KEY"
            log_error "Please ensure the SSH key exists and is accessible"
            exit 1
        fi
        SSH_KEY="$expanded_key"
    fi

    # Check for source files
    if [[ ! -f "$LOCAL_DIR/compose.yml" ]]; then
        log_error "compose.yml not found in $LOCAL_DIR"
        exit 1
    fi

    if [[ ! -f "$LOCAL_DIR/.env" ]]; then
        log_error ".env file not found in $LOCAL_DIR"
        log_error "Copy .env.example to .env and configure if needed"
        exit 1
    fi

    log_success "Prerequisites validated"
}

#-------------------------------------------------------------------------------
# LXC Health Check
#-------------------------------------------------------------------------------
check_lxc_status() {
    log_info "Checking LXC status..."

    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" "pct status $LXC_ID" &>/dev/null; then
        log_error "LXC $LXC_ID is not accessible or not running"
        log_error "Please ensure LXC is running before deploying"
        exit 1
    fi

    local status
    status=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" "pct status $LXC_ID")
    log_info "LXC status: $status"

    if [[ "$status" != "running" ]]; then
        log_error "LXC $LXC_ID is not running (status: $status)"
        exit 1
    fi

    log_success "LXC is running"
}

#-------------------------------------------------------------------------------
# Main Deployment Steps
#-------------------------------------------------------------------------------
create_directory() {
    log_info "[1/5] Creating directory in LXC..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" \
        "pct exec $LXC_ID -- mkdir -p $REMOTE_DIR"
    log_success "Directory created at $REMOTE_DIR"
}

copy_files_to_proxmox() {
    log_info "[2/5] Copying files to Proxmox temp..."

    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
        "$LOCAL_DIR/compose.yml" "root@${PROXMOX_HOST}:/tmp/arcane-compose.yml"

    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
        "$LOCAL_DIR/.env" "root@${PROXMOX_HOST}:/tmp/arcane-env"

    log_success "Files copied to /tmp/"
}

push_files_to_lxc() {
    log_info "[3/5] Pushing files to LXC..."

    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" \
        "pct push $LXC_ID /tmp/arcane-compose.yml $REMOTE_DIR/compose.yml"

    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" \
        "pct push $LXC_ID /tmp/arcane-env $REMOTE_DIR/.env"

    log_success "Files pushed to $REMOTE_DIR"
}

ensure_docker_compose() {
    log_info "[4/5] Ensuring docker-compose is installed..."

    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" "pct exec $LXC_ID -- bash -c '
        if command -v docker-compose >/dev/null 2>&1; then
            echo "docker-compose already installed"
        elif command -v docker compose >/dev/null 2>&1; then
            echo "docker compose (plugin) available"
        else
            echo "Installing docker-compose..."
            apt-get update && apt-get install -y docker-compose
        fi
    '"

    log_success "docker-compose ready"
}

deploy_container() {
    log_info "[5/5] Deploying Arcane container..."

    if [[ "${REDEPLOY:-false}" == "true" ]]; then
        log_warn "Redeploy mode: removing existing container..."
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" \
            "pct exec $LXC_ID -- docker rm -f arcane 2>/dev/null || true"
    fi

    # Remove any existing container (always, to handle updates)
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" \
        "pct exec $LXC_ID -- docker rm -f arcane 2>/dev/null || true"

    # Deploy with docker-compose
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" \
        "pct exec $LXC_ID -- bash -c 'cd $REMOTE_DIR && docker-compose up -d'"

    # Verify deployment
    sleep 3
    local container_status
    container_status=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" \
        "pct exec $LXC_ID -- docker inspect --format='{{.State.Status}}' arcane 2>/dev/null || echo 'not_found'")

    if [[ "$container_status" == "running" ]]; then
        log_success "Arcane container is running"
    else
        log_error "Container deployment may have failed (status: $container_status)"
        log_info "Check logs with: docker logs arcane"
    fi
}

cleanup() {
    log_info "Cleaning up temporary files..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" \
        "rm -f /tmp/arcane-compose.yml /tmp/arcane-env" || true
    log_success "Cleanup complete"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo "  Arcane Deployment Script"
    echo "  Target: LXC $LXC_ID @ $PROXMOX_HOST"
    echo "=============================================="
    echo ""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --redeploy)
                REDEPLOY="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Run deployment steps
    validate_prerequisites
    check_lxc_status
    create_directory
    copy_files_to_proxmox
    push_files_to_lxc
    ensure_docker_compose
    deploy_container
    cleanup

    echo ""
    echo "=============================================="
    echo "  Deployment Complete!"
    echo "=============================================="
    echo ""
    log_success "Access Arcane at: $APP_URL"
    echo ""
}

# Execute main function
main "$@"
