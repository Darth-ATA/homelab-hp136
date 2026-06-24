#!/bin/bash
# check-backup-status.sh — Monitor Proxmox backup job status
#
# Parses /var/log/pve/tasks/index for vzdump entries in the last 24h
# and alerts via Telegram when backups fail. Sends recovery notification
# when all backups return to healthy state.
#
# State tracking prevents alert spam (30 min cooldown).
#
# Cron example (05:30 daily, after backup window ends at 04:30):
#   30 5 * * * /usr/local/bin/check-backup-status.sh

set -Eeuo pipefail

# Ensure system commands are in PATH — cron has a minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ─── Configuration ────────────────────────────────────────────────────────────

# Source /root/.env for Telegram credentials (graceful fallback)
if [[ -f "/root/.env" ]]; then
    # shellcheck source=/dev/null
    source "/root/.env"
fi

VMIDS=(100 101 102 103 104 105)
declare -A VMID_NAMES
VMID_NAMES[100]="home-assistant"
VMID_NAMES[101]="docker"
VMID_NAMES[102]="tailscale"
VMID_NAMES[103]="adguard"
VMID_NAMES[104]="vaultwarden"
VMID_NAMES[105]="jellyfin"

INDEX_FILE="/var/log/pve/tasks/index"
LOG_FILE="/var/log/check-backup-status.log"

# Telegram bot (empty = no alerts — sourced from /root/.env)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# State tracking (prevents alert spam)
STATE_FILE="${STATE_FILE:-/var/tmp/check-backup-status.state}"
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
    logger -t "check-backup-status" -- "WARN: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
    logger -t "check-backup-status" -- "ERROR: $*"
}

log_ok() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: $*" >> "$LOG_FILE"
}

# ─── Dependency Check ─────────────────────────────────────────────────────────

check_deps() {
    local -a missing=()

    for cmd in awk logger curl; do
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
    # Restore previous state from disk
    read_state

    # Ensure log file exists and is writable
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot write to $LOG_FILE" >&2
        logger -t "check-backup-status" -- "ERROR: Cannot write to $LOG_FILE"
        exit 1
    }

    log_info "Checking backup job status..."

    local cutoff
    cutoff=$(date -d '24 hours ago' +%s)

    # Check if index file exists
    if [[ ! -f "$INDEX_FILE" ]]; then
        log_error "PVE task index not found: $INDEX_FILE"
        echo "ERROR: PVE task index not found: $INDEX_FILE" >&2
        exit 1
    fi

    # Parse PVE task index for vzdump entries in the last 24h
    # Index line format: UPID:node:pid:pstart:hex_ts:vzdump:vmid:user:... STATUS
    #
    # awk approach:
    #   - Filter by type=vzdump and VMID in our monitored list
    #   - Extract hex timestamp (field 5 by colon) and convert to epoch
    #   - Extract status (last whitespace-separated token of the line)
    #   - Only process entries within the 24h cutoff window
    declare -A failures=()

    while read -r _ vmid status; do
        if [[ "$status" != "OK" ]]; then
            failures["$vmid"]="$status"
            log_warn "Backup FAILED for VM $vmid (${VMID_NAMES[$vmid]:-unknown}): $status"
        fi
    done < <(awk -F: -v cutoff="$cutoff" '
        $6 == "vzdump" && $7 ~ /^(100|101|102|103|104|105)$/ {
            vmid = $7
            hex_ts = $5

            # Convert hex timestamp to epoch (works in gawk and mawk)
            ts = ("0x" hex_ts) + 0

            # Get status: last whitespace-separated token of entire line
            n = split($0, parts, " ")
            status = parts[n]
            gsub(/[^[:print:]]/, "", status)

            # Only process entries within cutoff window
            if (ts >= cutoff) {
                print ts, vmid, status
            }
        }
    ' "$INDEX_FILE" 2>/dev/null) || {
        log_error "awk parsing of PVE task index failed"
        echo "ERROR: awk parsing failed" >&2
        exit 1
    }

    local total_vms=${#VMIDS[@]}
    local failed_count=${#failures[@]}

    if [[ "$failed_count" -eq 0 ]]; then
        # All backups successful — handle recovery from previous failures
        local now_ts
        now_ts=$(date +'%Y-%m-%d %H:%M:%S')

        if [[ "$PREVIOUS_STATE" == "unhealthy" ]]; then
            local recovery_msg
            recovery_msg=$(cat <<-EOF
✅ *Backup Status — All OK*
All $total_vms backups completed successfully in the last 24h.
Host: $(hostname -s)
Time: $now_ts
EOF
)
            alert_via_telegram "$recovery_msg" || true
        fi

        write_state "healthy"
        log_ok "All $total_vms backups completed successfully"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: All backups completed successfully"
        exit 0

    else
        # Some backups failed — compose and send alert
        local now_ts
        now_ts=$(date +'%Y-%m-%d %H:%M:%S')

        local windows_start
        windows_start=$(date -d '24 hours ago' +'%Y-%m-%d %H:%M')

        # Build failure details string
        local failure_details=""
        for vmid in "${!failures[@]}"; do
            failure_details+="• VM $vmid (${VMID_NAMES[$vmid]:-unknown}) — ${failures[$vmid]}"$'\n'
        done

        local alert_msg
        alert_msg=$(cat <<-EOF
🚨 *Backup Failure Detected*
Failed: $failed_count of $total_vms backups

${failure_details}Host: $(hostname -s)
Window: $windows_start – $now_ts
EOF
)
        PREVIOUS_STATE="unhealthy"
        alert_via_telegram "$alert_msg" || true
        write_state "unhealthy"

        log_warn "Backup failures detected: $failed_count of $total_vms failed"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Backup failures detected ($failed_count of $total_vms)"
        exit 1
    fi
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

check_deps
main "$@"
