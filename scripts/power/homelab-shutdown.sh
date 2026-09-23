#!/usr/bin/env bash
# homelab-shutdown.sh — Conditional daily shutdown with Frigate exception
# Deployed via Terraform to /usr/local/bin/homelab-shutdown.sh
# Cron: 0 3 * * * root /usr/local/bin/homelab-shutdown.sh  (03:00 UTC = 00:00 ARG)

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────────
LOG_FILE="/var/log/homelab-shutdown.log"
LXC_DOCKER_ID=101
FRIGATE_CONTAINER_NAME="frigate"
TIMEZONE="America/Argentina/Buenos_Aires"
DRY_RUN=false

# ─── Helpers ────────────────────────────────────────────────────────────────────
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp="$(TZ="${TIMEZONE}" date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "[${timestamp}] [${level}] ${msg}" | tee -a "${LOG_FILE}"
}

# ─── Frigate Detection ──────────────────────────────────────────────────────────
check_frigate_docker() {
    # Check if Frigate container is running in LXC 101 (Docker host)
    if pct exec "${LXC_DOCKER_ID}" -- docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${FRIGATE_CONTAINER_NAME}$"; then
        log "INFO" "Frigate detectado corriendo en LXC ${LXC_DOCKER_ID} (Docker) — omitiendo apagado"
        return 0
    fi
    return 1
}

check_frigate_systemd() {
    # Check if Frigate runs as systemd service on Proxmox host
    if systemctl is-active --quiet "${FRIGATE_CONTAINER_NAME}" 2>/dev/null; then
        log "INFO" "Frigate detectado como systemd service en host — omitiendo apagado"
        return 0
    fi
    return 1
}

# ─── Main ───────────────────────────────────────────────────────────────────────
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                echo "Usage: $0 [--dry-run]"
                exit 1
                ;;
        esac
    done

    log "INFO" "=== Iniciando verificación de apagado programado ==="

    # Check both locations for Frigate
    if check_frigate_docker || check_frigate_systemd; then
        log "INFO" "Apagado CANCELADO: Frigate activo"
        exit 0
    fi

    log "WARN" "Sin Frigate activo — procediendo con apagado del host"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Ejecutaría: shutdown -h now"
        log "INFO" "[DRY-RUN] Apagado SIMULADO — no se apaga el host"
        exit 0
    fi

    log "INFO" "Ejecutando: shutdown -h now"

    # Give a brief grace period for any last-second operations
    sleep 5

    shutdown -h now
}

main "$@"