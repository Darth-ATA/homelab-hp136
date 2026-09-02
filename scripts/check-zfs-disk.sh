#!/bin/bash
# check-zfs-disk.sh — Monitor ZFS pool disk usage
#
# Checks ZFS pool usage and alerts via Telegram when usage exceeds
# configured threshold (default 80%). Lists top 5 space consumers.
# Runs once daily via cron.
#
# Cron example (daily at 09:00):
#   0 9 * * * /usr/local/bin/check-zfs-disk.sh -t 80

set -Eeuo pipefail

# Ensure system commands are in PATH — cron has a minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ─── Configuration ────────────────────────────────────────────────────────────

ZFS_POOL="rpool"
WARN_THRESHOLD=80
LOG_FILE="/var/log/check-zfs-disk.log"

# Source /root/.env for Telegram credentials (graceful fallback)
if [[ -f "/root/.env" ]]; then
    # shellcheck source=/dev/null
    source "/root/.env"
fi

# Telegram bot (empty = no alerts — sourced from /root/.env)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# State tracking (prevents Telegram alert spam - daily check so 24h cooldown)
STATE_FILE="${STATE_FILE:-/var/tmp/check-zfs-disk.state}"
STATE_COOLDOWN="${STATE_COOLDOWN:-86400}"  # 24 hours
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

    if [[ "$PREVIOUS_STATE" != "healthy" ]] && [[ "$elapsed" -lt "$STATE_COOLDOWN" ]]; then
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
    logger -t "check-zfs-disk" -- "WARN: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
    logger -t "check-zfs-disk" -- "ERROR: $*"
}

log_ok() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: $*" >> "$LOG_FILE"
}

# ─── Parse Options ────────────────────────────────────────────────────────────

parse_opts() {
    while getopts ":t:" opt; do
        case "$opt" in
            t) WARN_THRESHOLD="$OPTARG" ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
            :) echo "Option -$OPTARG requires an argument" >&2; exit 1 ;;
        esac
    done
}

# ─── Get Top 5 ZFS Datasets by Usage ──────────────────────────────────────────

get_top5_datasets() {
    # Get all datasets under the pool, sorted by used space (descending), top 5
    # Format: NAME USED
    zfs list -H -o name,used -r "$ZFS_POOL" 2>/dev/null | \
        sort -k2 -hr | \
        head -5 | \
        awk '{printf "  %s: %s\n", $1, $2}'
}

# ─── Main Check ───────────────────────────────────────────────────────────────

main() {
    parse_opts "$@"
    read_state

    # Ensure log file exists and is writable
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot write to $LOG_FILE" >&2
        logger -t "check-zfs-disk" -- "ERROR: Cannot write to $LOG_FILE"
        exit 1
    }

    log_info "Checking ZFS pool $ZFS_POOL disk usage..."

    # Get pool usage
    local pool_info
    pool_info=$(zfs list -H -o name,used,avail,refer "$ZFS_POOL" 2>/dev/null | head -1)

    if [[ -z "$pool_info" ]]; then
        log_error "Failed to get ZFS pool info for $ZFS_POOL"
        echo "ERROR: Cannot read ZFS pool $ZFS_POOL" >&2
        exit 1
    fi

    local pool_name used avail refer
    read -r pool_name used avail refer <<< "$pool_info"

    # Calculate usage percentage from pool's used + avail
    # zfs reports sizes in bytes or with suffix
    local used_bytes avail_bytes

    # Convert human-readable to bytes
    used_bytes=$(zfs get -Hp used "$ZFS_POOL" 2>/dev/null | awk '{print $3}')
    avail_bytes=$(zfs get -Hp available "$ZFS_POOL" 2>/dev/null | awk '{print $3}')

    if [[ -z "$used_bytes" || -z "$avail_bytes" || "$used_bytes" == "-" || "$avail_bytes" == "-" ]]; then
        log_error "Failed to get ZFS pool used/available bytes"
        exit 1
    fi

    local total_bytes=$((used_bytes + avail_bytes))
    local usage=$(( used_bytes * 100 / total_bytes ))

    local now_ts
    now_ts=$(date +'%Y-%m-%d %H:%M:%S')

    # Format sizes for display
    local used_str avail_str
    used_str=$(numfmt --to=iec "$used_bytes" 2>/dev/null || echo "$((used_bytes / 1073741824))G")
    avail_str=$(numfmt --to=iec "$avail_bytes" 2>/dev/null || echo "$((avail_bytes / 1073741824))G")

    if [[ "$usage" -ge "$WARN_THRESHOLD" ]]; then
        # ─── Warning ──────────────────────────────────────────────────────────
        local top5
        top5=$(get_top5_datasets)

        local msg
        msg=$(cat <<-EOF
⚠️ *ZFS Pool Warning*
Pool: $ZFS_POOL
Usage: $usage% ($used_str used / $avail_str free)
Host: $(hostname -s)
Time: $now_ts

*Top 5 space consumers:*
$top5
EOF
)
        PREVIOUS_STATE="warning"
        alert_via_telegram "$msg" || true
        write_state "warning"

        # Always email for warning conditions
        echo "$msg" | mail -s "ZFS POOL WARNING: $usage% on $(hostname -s)" root || \
            log_warn "Failed to send email alert"

        log_warn "ZFS pool $ZFS_POOL WARNING: $usage% used ($used_str / $avail_str)"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: ZFS pool $ZFS_POOL at $usage% — threshold ${WARN_THRESHOLD}%"
        exit 1

    else
        # ─── Healthy ──────────────────────────────────────────────────────────
        # If previously in warning state, send recovery notification
        if [[ "$PREVIOUS_STATE" != "healthy" ]]; then
            local recovery_msg
            recovery_msg=$(cat <<-EOF
✅ *ZFS Pool Recovered*
Pool: $ZFS_POOL
Usage: now $usage% (was above ${WARN_THRESHOLD}%)
Host: $(hostname -s)
Time: $now_ts
EOF
)
            alert_via_telegram "$recovery_msg" || true
        fi

        write_state "healthy"
        log_ok "ZFS pool $ZFS_POOL healthy: $usage% used ($used_str / $avail_str)"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: ZFS pool $ZFS_POOL healthy ($usage%)"
        exit 0
    fi
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

check_deps() {
    local -a missing=()

    for cmd in zfs awk mail logger curl numfmt; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required commands: ${missing[*]}" >&2
        exit 1
    fi
}

check_deps
main "$@"