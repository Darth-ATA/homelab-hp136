#!/usr/bin/env bash
# homelab-suspend.sh — Conditional daily suspend with Frigate exception
# Deployed via Terraform to /usr/local/bin/homelab-suspend.sh
# Cron: 0 0 * * * root /usr/local/bin/homelab-suspend.sh  (00:00 local time = 00:00 Spain)

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────────
LOG_FILE="/var/log/homelab-suspend.log"
LXC_DOCKER_ID=101
FRIGATE_CONTAINER_NAME="frigate"
TIMEZONE="Europe/Madrid"
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
        log "INFO" "Frigate detectado corriendo en LXC ${LXC_DOCKER_ID} (Docker) — omitiendo suspensión"
        return 0
    fi
    return 1
}

check_frigate_systemd() {
    # Check if Frigate runs as systemd service on Proxmox host
    if systemctl is-active --quiet "${FRIGATE_CONTAINER_NAME}" 2>/dev/null; then
        log "INFO" "Frigate detectado como systemd service en host — omitiendo suspensión"
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

    log "INFO" "=== Iniciando verificación de suspensión programada ==="

    # Check both locations for Frigate
    if check_frigate_docker || check_frigate_systemd; then
        log "INFO" "Suspensión CANCELADA: Frigate activo"
        exit 0
    fi

    log "WARN" "Sin Frigate activo — procediendo con suspensión del host (S3)"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Ejecutaría: systemctl suspend"
        log "INFO" "[DRY-RUN] Suspensión SIMULADA — no se suspende el host"
        exit 0
    fi

    log "INFO" "Ejecutando: systemctl suspend"

    # Set RTC wake alarm for next morning (07:00 ARG = 10:00 UTC) before suspending
    log "INFO" "Configurando alarma RTC para despertar mañana..."
    /usr/local/bin/homelab-set-wake-alarm.sh

    # Give a brief grace period for any last-second operations
    sleep 5

    systemctl suspend
}

main "$@"