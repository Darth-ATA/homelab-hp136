#!/bin/bash
# sonarr-healthcheck.sh — Monitor Sonarr stack health and alert via Proxmox
#
# Runs on the Proxmox host. Checks Sonarr API health + basic internet
# connectivity from the LXC. If something's wrong, logs to syslog and
# optionally sends email via sendmail.
#
# State tracking avoids alert spam — only alerts on state transitions
# (healthy → unhealthy) or if the problem persists beyond a cooldown.
#
# Cron example (every 5 minutes):
#   */5 * * * * /usr/local/bin/sonarr-healthcheck.sh
#
# Dependencies: curl, logger, sendmail (optional for email alerts)

set -Eeuo pipefail

# Ensure system commands are in PATH — cron has a minimal PATH that excludes /usr/sbin
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ─── Configuration ────────────────────────────────────────────────────────────

# Sonarr
SONARR_URL="${SONARR_URL:-http://192.168.1.142:8989}"
SONARR_API_KEY="${SONARR_API_KEY:?SONARR_API_KEY is required - set it in the cron environment or pass as env var}"

# Internet test target — caught the TP-Link DoS issue blocking LXC outbound
INTERNET_TEST_URL="${INTERNET_TEST_URL:-https://skyhook.sonarr.tv}"

# LXC container ID (for remediation)
LXC_ID="${LXC_ID:-101}"
SONARR_CONTAINER="${SONARR_CONTAINER:-sonarr}"

# Alert email (empty = no email sent)
ALERT_EMAIL="${ALERT_EMAIL:-}"

# Telegram bot (empty = no telegram alerts)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-<your-telegram-bot-token>}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-<your-telegram-chat-id>}"

# State tracking
STATE_FILE="${STATE_FILE:-/var/tmp/sonarr-healthcheck.state}"
LOG_FILE="${LOG_FILE:-/var/log/sonarr-healthcheck.log}"

# Alert cooldown in seconds — don't re-alert for the same issue
ALERT_COOLDOWN="${ALERT_COOLDOWN:-1800}"  # 30 minutes

# Remediation: try to restart Sonarr on failure
REMEDIATE="${REMEDIATE:-true}"

# ─── Logging ──────────────────────────────────────────────────────────────────

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$LOG_FILE"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*" >> "$LOG_FILE"
    logger -t "sonarr-healthcheck" -- "WARN: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
    logger -t "sonarr-healthcheck" -- "ERROR: $*"
}

log_ok() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: $*" >> "$LOG_FILE"
}

log_recovery() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] RECOVERY: $*" >> "$LOG_FILE"
    logger -t "sonarr-healthcheck" -- "RECOVERY: $*"
}

# ─── State Tracking ───────────────────────────────────────────────────────────

read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_FILE"
    fi
    # Defaults if state file is missing or partial
    PREVIOUS_STATE="${PREVIOUS_STATE:-healthy}"
    LAST_ALERT_TIME="${LAST_ALERT_TIME:-0}"
    REMEDIATION_COUNT="${REMEDIATION_COUNT:-0}"
}

write_state() {
    local state="$1"
    local alert_time="${2:-$LAST_ALERT_TIME}"

    cat > "$STATE_FILE" <<-EOF
PREVIOUS_STATE="$state"
LAST_ALERT_TIME="$alert_time"
REMEDIATION_COUNT="$REMEDIATION_COUNT"
EOF
}

should_alert() {
    local now
    now=$(date +%s)

    # Alert if transitioning to unhealthy OR if cooldown has expired
    if [[ "$PREVIOUS_STATE" == "healthy" ]]; then
        return 0  # new issue — alert now
    fi

    if (( now - LAST_ALERT_TIME >= ALERT_COOLDOWN )); then
        return 0  # cooldown expired — re-alert
    fi

    return 1  # don't alert, still in cooldown
}

# ─── Alerting ─────────────────────────────────────────────────────────────────

alert_via_sendmail() {
    local subject="$1"
    local body="$2"

    if [[ -z "$ALERT_EMAIL" ]]; then
        return 0  # no email configured
    fi

    if ! command -v sendmail &>/dev/null; then
        log_warn "sendmail not available, skipping email alert"
        return 1
    fi

    {
        echo "To: $ALERT_EMAIL"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | sendmail -t 2>/dev/null || {
        log_error "Failed to send email alert to $ALERT_EMAIL"
        return 1
    }

    log_info "Email alert sent to $ALERT_EMAIL"
}

alert_via_telegram() {
    local message="$1"

    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return 0  # telegram not configured
    fi

    local response
    response=$(curl -sf --connect-timeout 10 \
        -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$message" \
        -d "parse_mode=HTML" 2>&1) || {
        log_error "Failed to send Telegram alert: $response"
        return 1
    }

    log_info "Telegram alert sent to chat $TELEGRAM_CHAT_ID"
}

alert() {
    local issue="$1"
    local detail="$2"
    local now
    now=$(date +%s)

    if ! should_alert; then
        log_info "Alert suppressed (cooldown active, last alert was $(( (now - LAST_ALERT_TIME) / 60 )) minutes ago)"
        return 0
    fi

    local message_body
    message_body=$(cat <<-EOF
<b>⚠️ Sonarr Health Alert</b>

<b>Issue:</b> $issue
<b>Detail:</b> $detail
<b>Host:</b> $(hostname)
<b>Time:</b> $(date '+%Y-%m-%d %H:%M:%S')
<b>Remediation attempts:</b> $REMEDIATION_COUNT
EOF
)

    log_error "$issue — $detail"

    # Send alerts
    alert_via_telegram "$message_body" || true
    alert_via_sendmail "[ALERT] Sonarr Health: $issue" "$message_body" || true

    write_state "unhealthy" "$now"
}

# ─── Remediation ──────────────────────────────────────────────────────────────

remediate() {
    if [[ "$REMEDIATE" != "true" ]]; then
        return 1
    fi

    log_warn "Attempting remediation (restarting Sonarr container)..."

    local result
    result=$(pct exec "$LXC_ID" -- docker restart "$SONARR_CONTAINER" 2>&1) || {
        log_error "Remediation failed: could not restart $SONARR_CONTAINER in LXC $LXC_ID — $result"
        REMEDIATION_COUNT=$((REMEDIATION_COUNT + 1))
        write_state "unhealthy"
        return 1
    }

    REMEDIATION_COUNT=$((REMEDIATION_COUNT + 1))
    log_info "Remediation OK: $SONARR_CONTAINER restarted (attempt $REMEDIATION_COUNT)"
    write_state "unhealthy"  # stay in alert state until next check verifies recovery

    # Wait briefly for Sonarr to come up
    sleep 5
    return 0
}

# ─── Health Checks ────────────────────────────────────────────────────────────

check_internet() {
    # Uses the Proxmox host's connectivity — if this fails, the whole host
    # has no internet and that's a different problem.
    curl -sf --connect-timeout 10 "$INTERNET_TEST_URL" >/dev/null 2>&1
}

check_sonarr_api() {
    curl -sf --connect-timeout 10 \
        -H "X-Api-Key: $SONARR_API_KEY" \
        "$SONARR_URL/api/v3/system/status" >/dev/null 2>&1
}

check_sonarr_health() {
    local health_result
    health_result=$(curl -sf --connect-timeout 10 \
        -H "X-Api-Key: $SONARR_API_KEY" \
        "$SONARR_URL/api/v3/health" 2>/dev/null) || return 1

    # Check if health endpoint returned issues
    if echo "$health_result" | grep -q '"source"' 2>/dev/null; then
        # Classify issues by severity
        local critical_issues
        local warning_issues

        critical_issues=$(echo "$health_result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data:
        if item.get('type') == 'error':
            print(f\"  - {item.get('message', 'unknown')}\")
except: pass
" 2>/dev/null)

        warning_issues=$(echo "$health_result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data:
        if item.get('type') == 'warning':
            print(f\"  - {item.get('message', 'unknown')} ({item.get('type', 'unknown')})\")
except: pass
" 2>/dev/null)

        if [[ -n "$critical_issues" ]]; then
            echo "CRITICAL:$critical_issues"
            return 2  # critical health issues
        elif [[ -n "$warning_issues" ]]; then
            echo "WARNING:$warning_issues"
            return 3  # warnings only
        fi
    fi

    return 0  # healthy
}

check_lxc_connectivity() {
    # Check if LXC is reachable and the Docker daemon is running
    pct exec "$LXC_ID" -- docker info >/dev/null 2>&1
}

check_container_running() {
    local status
    status=$(pct exec "$LXC_ID" -- docker inspect --format='{{.State.Status}}' "$SONARR_CONTAINER" 2>/dev/null) || return 1
    [[ "$status" == "running" ]]
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    # Ensure log file exists
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot write to $LOG_FILE" >&2
        logger -t "sonarr-healthcheck" -- "ERROR: Cannot write to $LOG_FILE"
        exit 1
    }

    # Read previous state
    read_state

    log_info "Starting health check (previous state: $PREVIOUS_STATE)..."

    local all_healthy=true
    local error_details=""
    local health_issues=""

    # ── Check 1: Internet connectivity ──
    if ! check_internet; then
        all_healthy=false
        error_details+="Internet unreachable (cannot reach $INTERNET_TEST_URL)"$'\n'
    fi

    # ── Check 2: LXC + Docker reachable ──
    if ! check_lxc_connectivity; then
        all_healthy=false
        error_details+="LXC $LXC_ID unreachable or Docker not running"$'\n'
    fi

    # ── Check 3: Sonarr container running ──
    if ! check_container_running; then
        all_healthy=false
        error_details+="Sonarr container not running in LXC $LXC_ID"$'\n'
    fi

    # ── Check 4: Sonarr API reachable ──
    if ! check_sonarr_api; then
        all_healthy=false
        error_details+="Sonarr API unreachable at $SONARR_URL"$'\n'
    fi

    # ── Check 5: Sonarr health endpoint ──
    local health_exit_code=0
    health_issues=$(check_sonarr_health) || health_exit_code=$?

    if [[ $health_exit_code -eq 2 ]]; then
        # Critical issues found — alert
        all_healthy=false
        critical_part="${health_issues#CRITICAL:}"
        error_details+="Sonarr critical health issues:$critical_part"$'\n'
    elif [[ $health_exit_code -eq 3 ]]; then
        # Warnings only — log but don't trigger alert
        warning_part="${health_issues#WARNING:}"
        log_info "Sonarr health warnings (non-critical):$warning_part"
    elif [[ $health_exit_code -eq 1 ]]; then
        # Endpoint unreachable — already caught by check_sonarr_api
        log_warn "Sonarr health endpoint unreachable (API may still be starting)"
    fi

    # ── Decision ──────────────────────────

    if [[ "$all_healthy" == true ]]; then
        if [[ "$PREVIOUS_STATE" != "healthy" ]]; then
            log_recovery "Sonarr stack is healthy again"
            local recovery_msg
            recovery_msg=$(cat <<-EOF
<b>✅ Sonarr Health Restored</b>

All checks passed at $(date '+%Y-%m-%d %H:%M:%S')
<b>Host:</b> $(hostname)
EOF
)
            alert_via_telegram "$recovery_msg" || true
            alert_via_sendmail "[RECOVERY] Sonarr Health Restored" "$recovery_msg" || true
        else
            log_ok "All checks passed"
        fi
        write_state "healthy"
        exit 0

    else
        # Something is wrong
        alert "Sonarr stack unhealthy" "$error_details"

        # Try remediation
        remediate || true

        exit 2
    fi
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

# Verify required commands
for cmd in curl logger; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Missing required command: $cmd" >&2
        exit 1
    fi
done

main "$@"
