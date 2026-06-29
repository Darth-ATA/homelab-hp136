#!/bin/bash
# check-lxc-internet.sh — Monitor internet connectivity from inside LXC 101
#
# Tests internet reachability FROM inside the LXC container, not from the
# Proxmox host. This catches router-level blocks (like the EX520v DoS
# Protection) that block specific container IPs while the host itself
# still has internet — exactly what happened in June 2026.
#
# How it works:
#   1. Runs curl --connect-timeout 10 inside LXC 101 (via pct exec)
#   2. If HTTP code != 2xx/3xx or curl fails → alert
#   3. On first healthy check after an alert → recovery notification
#
# State tracking prevents alert spam. Telegram bot is configured via
# environment variables (set in cron or /root/.env).
#
# Cron example (every 5 minutes):
#   */5 * * * * /usr/local/bin/check-lxc-internet.sh
#
# Dependencies: curl (on host + inside LXC), logger, pct

set -Eeuo pipefail

# Ensure system commands are in PATH — cron has a minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ─── Configuration ────────────────────────────────────────────────────────────

# LXC container ID and test target
LXC_ID="${LXC_ID:-101}"
TEST_URL="${TEST_URL:-https://google.com}"
TEST_TIMEOUT="${TEST_TIMEOUT:-10}"  # seconds

# Telegram bot (empty = no alerts — sourced from /root/.env or env var)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# State tracking
STATE_FILE="${STATE_FILE:-/var/tmp/check-lxc-internet.state}"
LOG_FILE="${LOG_FILE:-/var/log/check-lxc-internet.log}"
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

    local response
    response=$(curl -sf --connect-timeout 10 \
        -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$message" \
        -d "parse_mode=HTML" 2>&1) || {
        log_warn "Failed to send Telegram alert: $response"
        return 0
    }

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
    logger -t "check-lxc-internet" -- "WARN: $*"
}

log_ok() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: $*" >> "$LOG_FILE"
}

# ─── Main Check ───────────────────────────────────────────────────────────────

main() {
    # Source environment — cron doesn't load /root/.env automatically
    # shellcheck source=/dev/null
    source "/root/.env" 2>/dev/null || log_info "No /root/.env found, using env vars"

    # Restore previous state from disk
    read_state

    # Ensure log file exists and is writable
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot write to $LOG_FILE" >&2
        logger -t "check-lxc-internet" -- "ERROR: Cannot write to $LOG_FILE"
        exit 1
    }

    log_info "Checking LXC $LXC_ID internet connectivity (target: $TEST_URL)..."

    # ── Run curl INSIDE the LXC ─────────────────────────────────────────────

    local http_code=""

    # pct exec runs inside the LXC. We capture output and exit code separately.
    http_code=$(pct exec "$LXC_ID" -- curl -s -o /dev/null -w '%{http_code}' \
        --connect-timeout "$TEST_TIMEOUT" "$TEST_URL" 2>/dev/null) || true

    # If http_code is empty or not a number, something went wrong
    if [[ -z "$http_code" ]]; then
        http_code="000"
    fi

    # Determine success: 2xx or 3xx are OK, 000 means connection failed
    local success=false
    if [[ "$http_code" =~ ^[23][0-9]{2}$ ]]; then
        success=true
    fi

    # ── Decision Logic ───────────────────────────────────────────────────────

    if [[ "$success" == true ]]; then
        # LXC has internet — all good

        if [[ "$PREVIOUS_STATE" != "healthy" ]]; then
            # Recovering from an unhealthy state — send recovery notification
            local recovery_msg
            recovery_msg=$(cat <<-EOF
✅ <b>LXC $LXC_ID Internet Restored</b>

LXC $LXC_ID can now reach $TEST_URL (HTTP $http_code)
<b>Host:</b> $(hostname -s)
<b>Time:</b> $(date +'%Y-%m-%d %H:%M:%S')
EOF
)
            alert_via_telegram "$recovery_msg" || true
            log_info "Recovery: LXC $LXC_ID internet restored (HTTP $http_code)"
        else
            log_ok "LXC $LXC_ID internet OK (HTTP $http_code → $TEST_URL)"
        fi

        write_state "healthy"
        exit 0

    else
        # Internet unreachable from LXC
        log_warn "LXC $LXC_ID cannot reach $TEST_URL (HTTP $http_code)"

        # Build alert message
        local alert_msg
        if [[ "$http_code" == "000" ]]; then
            alert_msg=$(cat <<-EOF
🚨 <b>LXC $LXC_ID Sin Internet</b>

<b>Detalle:</b> No se puede alcanzar $TEST_URL desde LXC $LXC_ID
<b>HTTP Code:</b> $http_code (timeout / sin conexión)
<b>Host:</b> $(hostname -s)
<b>Hora:</b> $(date +'%Y-%m-%d %H:%M:%S')

<b>Posibles causas:</b>
• Router bloqueó LXC por DoS Protection (EX520v)
• Firewall de Proxmox bloqueando salida
• Router sin NAT para $LXC_ID
• DNS no resuelve dentro del LXC

<b>Quick check:</b>
  ssh root@192.168.1.134 "pct exec $LXC_ID -- ping -c 2 192.168.1.1"
  ssh root@192.168.1.134 "pct exec $LXC_ID -- curl -s $TEST_URL"
EOF
)
        else
            alert_msg=$(cat <<-EOF
⚠️ <b>LXC $LXC_ID Internet Anómalo</b>

<b>Detalle:</b> HTTP $http_code al consultar $TEST_URL
<b>Host:</b> $(hostname -s)
<b>Hora:</b> $(date +'%Y-%m-%d %H:%M:%S')
EOF
)
        fi

        alert_via_telegram "$alert_msg" || true
        write_state "unhealthy"
        exit 2
    fi
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

# Verify required commands
for cmd in curl logger pct; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Missing required command: $cmd" >&2
        exit 1
    fi
done

main "$@"
