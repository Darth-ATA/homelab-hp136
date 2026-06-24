#!/bin/bash
# check-backup-disk.sh — Monitor backup storage disk usage
#
# Checks df on /var/lib/vz/dump and alerts via Telegram + email
# when usage exceeds configured thresholds. State tracking prevents
# Telegram alert spam (30 min cooldown). Email alerts always fire.
#
# Cron example (every 60 minutes):
#   */60 * * * * /usr/local/bin/check-backup-disk.sh -w 80 -c 90

set -Eeuo pipefail

# Ensure system commands are in PATH — cron has a minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ─── Configuration ────────────────────────────────────────────────────────────

BACKUP_STORAGE="/var/lib/vz/dump"
WARN_THRESHOLD=80
CRIT_THRESHOLD=90
LOG_FILE="/var/log/check-backup-disk.log"

# Source /root/.env for Telegram credentials (graceful fallback)
if [[ -f "/root/.env" ]]; then
    # shellcheck source=/dev/null
    source "/root/.env"
fi

# Telegram bot (empty = no alerts — sourced from /root/.env)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# State tracking (prevents Telegram alert spam)
STATE_FILE="${STATE_FILE:-/var/tmp/check-backup-disk.state}"
STATE_COOLDOWN="${STATE_COOLDOWN:-1800}"  # 30 minutes
PREVIOUS_STATE="${PREVIOUS_STATE:-healthy}"
LAST_ALERT_TIME="${LAST_ALERT_TIME:-0}"

# ─── State Tracking ───────────────────────────────────────────────────────────

read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_FILE"
    fi
    PREVIOUS_STATE="${PREVIOUS_STATE:-healthy}"
    LAST_ALERT_TIME="${LAST_ALERT_TIME:-0}"
}

write_state() {
    local state="$1"
    cat > "$STATE_FILE" <<-EOF
PREVIOUS_STATE="$state"
LAST_ALERT_TIME="$LAST_ALERT_TIME"
EOF
}

# ─── Telegram Alerts ──────────────────────────────────────────────────────────

alert_via_telegram() {
    local message="$1"

    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return 0
    fi

    local now
    now=$(date +%s)
    local elapsed=$((now - LAST_ALERT_TIME))

    if [[ "$PREVIOUS_STATE" == "unhealthy" ]] && [[ "$elapsed" -lt "$STATE_COOLDOWN" ]]; then
        return 0  # Cooldown active
    fi

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        --data-urlencode "parse_mode=Markdown" \
        -o /dev/null 2>/dev/null || log_warn "Failed to send Telegram alert"

    LAST_ALERT_TIME="$now"
    write_state "$PREVIOUS_STATE"
    log_info "Telegram alert sent to chat $TELEGRAM_CHAT_ID"
}

# ─── Logging ──────────────────────────────────────────────────────────────────

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$LOG_FILE"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*" >> "$LOG_FILE"
    logger -t "check-backup-disk" -- "WARN: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
    logger -t "check-backup-disk" -- "ERROR: $*"
}

log_ok() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: $*" >> "$LOG_FILE"
}

# ─── Parse Options ────────────────────────────────────────────────────────────

parse_opts() {
    while getopts ":w:c:" opt; do
        case "$opt" in
            w) WARN_THRESHOLD="$OPTARG" ;;
            c) CRIT_THRESHOLD="$OPTARG" ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
            :) echo "Option -$OPTARG requires an argument" >&2; exit 1 ;;
        esac
    done
}

# ─── Dependency Check ─────────────────────────────────────────────────────────

check_deps() {
    local -a missing=()

    for cmd in df awk mail logger curl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required commands: ${missing[*]}" >&2
        exit 1
    fi
}

# ─── Main Check ───────────────────────────────────────────────────────────────

main() {
    parse_opts "$@"
    read_state

    # Ensure log file exists and is writable
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot write to $LOG_FILE" >&2
        logger -t "check-backup-disk" -- "ERROR: Cannot write to $LOG_FILE"
        exit 1
    }

    log_info "Checking backup storage disk usage..."

    # Get disk usage percentage, used, and total
    local usage_str used_str total_str

    usage_str=$(df "$BACKUP_STORAGE" | awk 'NR==2 {gsub(/%/,""); print $5}') || true
    used_str=$(df -h "$BACKUP_STORAGE" | awk 'NR==2 {print $3}') || true
    total_str=$(df -h "$BACKUP_STORAGE" | awk 'NR==2 {print $2}') || true

    if [[ -z "$usage_str" ]]; then
        log_error "Failed to get disk usage for $BACKUP_STORAGE"
        echo "ERROR: Cannot read disk usage for $BACKUP_STORAGE" >&2
        exit 1
    fi

    local usage=$((usage_str + 0))
    local now_ts
    now_ts=$(date +'%Y-%m-%d %H:%M:%S')

    if [[ "$usage" -ge "$CRIT_THRESHOLD" ]]; then
        # ─── Critical ─────────────────────────────────────────────────────────
        local msg
        msg=$(cat <<-EOF
🚨 *Backup Disk CRITICAL*
Usage: $usage% ($used_str / $total_str)
Path: $BACKUP_STORAGE
Host: $(hostname -s)
Time: $now_ts
EOF
)
        PREVIOUS_STATE="critical"
        alert_via_telegram "$msg" || true
        write_state "critical"

        # Always email for critical conditions
        echo "$msg" | mail -s "BACKUP DISK CRITICAL: $usage% on $(hostname -s)" root || \
            log_warn "Failed to send email alert"

        log_error "Backup storage CRITICAL: $usage% used ($used_str / $total_str)"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] CRITICAL: Backup storage at $usage% — threshold ${CRIT_THRESHOLD}%"
        exit 2

    elif [[ "$usage" -ge "$WARN_THRESHOLD" ]]; then
        # ─── Warning ──────────────────────────────────────────────────────────
        local msg
        msg=$(cat <<-EOF
⚠️ *Backup Disk Warning*
Usage: $usage% ($used_str / $total_str)
Path: $BACKUP_STORAGE
Host: $(hostname -s)
Time: $now_ts
EOF
)
        PREVIOUS_STATE="warning"
        alert_via_telegram "$msg" || true
        write_state "warning"

        # Always email for warning conditions
        echo "$msg" | mail -s "BACKUP DISK WARNING: $usage% on $(hostname -s)" root || \
            log_warn "Failed to send email alert"

        log_warn "Backup storage WARNING: $usage% used ($used_str / $total_str)"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: Backup storage at $usage% — threshold ${WARN_THRESHOLD}%"
        exit 1

    else
        # ─── Healthy ──────────────────────────────────────────────────────────
        # If previously in warning or critical state, send recovery notification
        if [[ "$PREVIOUS_STATE" != "healthy" ]]; then
            local recovery_msg
            recovery_msg=$(cat <<-EOF
✅ *Backup Disk Recovered*
Usage: now $usage% (was above ${WARN_THRESHOLD}%)
Path: $BACKUP_STORAGE
Host: $(hostname -s)
Time: $now_ts
EOF
)
            alert_via_telegram "$recovery_msg" || true
        fi

        write_state "healthy"
        log_ok "Backup storage healthy: $usage% used ($used_str / $total_str)"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: Backup storage healthy ($usage%)"
        exit 0
    fi
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

check_deps
main "$@"
