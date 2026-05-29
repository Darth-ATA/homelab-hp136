#!/bin/bash
# check-backup-disk.sh - Monitor backup storage disk usage
# Installed on Proxmox host, runs via cron (check-disk timer)
# Alerts via syslog + mail when backup storage exceeds thresholds
#
# Usage: ./check-backup-disk.sh [options]
# Options:
#   -w PCT    Warning threshold (default: 80)
#   -c PCT    Critical threshold (default: 90)
#   -e EMAIL  Alert recipient (default: root)

set -Eeuo pipefail

SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
BACKUP_STORAGE="/var/lib/vz/dump"
WARN_THRESHOLD=80
CRIT_THRESHOLD=90
ALERT_EMAIL="root"

# Logging
log_info() {
    logger -t "$SCRIPT_NAME" "INFO: $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_warn() {
    logger -t "$SCRIPT_NAME" "WARN: $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

log_error() {
    logger -t "$SCRIPT_NAME" "ERROR: $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WARN_THRESHOLD="$2"; shift 2 ;;
        -c) CRIT_THRESHOLD="$2"; shift 2 ;;
        -e) ALERT_EMAIL="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,9p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate thresholds
if [[ "$WARN_THRESHOLD" -ge "$CRIT_THRESHOLD" ]]; then
    log_error "Warning threshold ($WARN_THRESHOLD) must be lower than critical ($CRIT_THRESHOLD)"
    exit 1
fi

# Check dependencies
for cmd in df awk mail; do
    command -v "$cmd" &>/dev/null || { log_error "Required command not found: $cmd"; exit 1; }
done

# Validate backup storage exists
if [[ ! -d "$BACKUP_STORAGE" ]]; then
    log_error "Backup storage directory does not exist: $BACKUP_STORAGE"
    exit 1
fi

# Get disk usage
usage=$(df "$BACKUP_STORAGE" | awk 'NR==2 {gsub(/%/,""); print $5}')
if [[ -z "${usage:-}" ]]; then
    log_error "Failed to get disk usage for $BACKUP_STORAGE"
    exit 1
fi

used=$(df -h "$BACKUP_STORAGE" | awk 'NR==2 {print $3}')
total=$(df -h "$BACKUP_STORAGE" | awk 'NR==2 {print $2}')

log_info "Backup storage usage: ${usage}% ($used / $total)"

if [[ "$usage" -ge "$CRIT_THRESHOLD" ]]; then
    subject="[CRITICAL] Backup storage at ${usage}% on $(hostname)"
    body="Backup storage ${BACKUP_STORAGE} is critically full: ${usage}% used ($used / $total)"
    log_error "$body"
    echo "$body" | mail -s "$subject" "$ALERT_EMAIL" 2>/dev/null || log_error "Mail delivery failed"
    exit 2
elif [[ "$usage" -ge "$WARN_THRESHOLD" ]]; then
    subject="[WARNING] Backup storage at ${usage}% on $(hostname)"
    body="Backup storage ${BACKUP_STORAGE} is getting full: ${usage}% used ($used / $total)"
    log_warn "$body"
    echo "$body" | mail -s "$subject" "$ALERT_EMAIL" 2>/dev/null || log_error "Mail delivery failed"
    exit 1
fi

exit 0
