#!/bin/bash
# check-lxc-internet.sh — Monitor internet connectivity from inside LXC 101
#
# Tests internet reachability FROM inside the LXC container, not from the
# Proxmox host. Catches router-level blocks (like EX520v DoS Protection)
# that block specific container IPs while the host itself still has internet.
#
# Architecture (v2):
#   1. curl --connect-timeout 10 inside LXC 101 (via pct exec)
#   2. If first attempt fails → immediate retry after 30s (catches brief glitches)
#   3. If retry also fails → ping gateway for diagnostic context
#   4. Only alerts after REQUIRED_FAILURES consecutive failures (default: 2)
#   5. Recovery notification sent when connectivity returns after alert state
#
# State file: /var/tmp/check-lxc-internet.state
#   Tracks PREVIOUS_STATE (healthy/unhealthy), LAST_ALERT_TIME, CONSECUTIVE_FAILURES
#
# Cron: */5 * * * * root /usr/local/bin/check-lxc-internet.sh
#
# Dependencies: curl (on host + inside LXC), ping (inside LXC), logger, pct

set -Eeuo pipefail

# Ensure system commands are in PATH — cron has a minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ─── Configuration ────────────────────────────────────────────────────────────

# Which container to test and what URL to hit
LXC_ID="${LXC_ID:-101}"
TEST_URL="${TEST_URL:-https://google.com}"
TEST_TIMEOUT="${TEST_TIMEOUT:-10}"           # seconds per curl attempt
RETRY_DELAY="${RETRY_DELAY:-30}"             # seconds between attempt and retry
REQUIRED_FAILURES="${REQUIRED_FAILURES:-2}"   # consecutive failures before alert
GATEWAY="${GATEWAY:-10.10.10.1}"             # for diagnostic ping

# Telegram bot (empty = no alerts — sourced from /root/.env or env var)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# State tracking
STATE_FILE="${STATE_FILE:-/var/tmp/check-lxc-internet.state}"
LOG_FILE="${LOG_FILE:-/var/log/check-lxc-internet.log}"
STATE_COOLDOWN="${STATE_COOLDOWN:-1800}"  # 30 minutes between re-alerts

# ─── State Tracking ───────────────────────────────────────────────────────────

read_state() {
    PREVIOUS_STATE="${PREVIOUS_STATE:-healthy}"
    LAST_ALERT_TIME="${LAST_ALERT_TIME:-0}"
    CONSECUTIVE_FAILURES="${CONSECUTIVE_FAILURES:-0}"
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_FILE"
    fi
}

write_state() {
    local state="$1"
    cat > "$STATE_FILE" <<-EOF
PREVIOUS_STATE="$state"
LAST_ALERT_TIME="$LAST_ALERT_TIME"
CONSECUTIVE_FAILURES="$CONSECUTIVE_FAILURES"
EOF
}

# ─── Helpers ──────────────────────────────────────────────────────────────────

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$LOG_FILE"; }
log_ok()   { echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: $*" >> "$LOG_FILE"; }
log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*" >> "$LOG_FILE"
    logger -t "check-lxc-internet" -- "WARN: $*"
}

# Run curl inside the LXC and return just the HTTP status code.
# Returns "000" on any failure (timeout, connection refused, etc.).
check_curl() {
    pct exec "$LXC_ID" -- curl -s -o /dev/null -w '%{http_code}' \
        --connect-timeout "$TEST_TIMEOUT" "$TEST_URL" 2>/dev/null || echo "000"
}

# Ping the gateway from inside the LXC for diagnostic purposes.
# Returns the summary line (e.g., "2 packets transmitted, 2 received, 0% packet loss").
check_gateway_ping() {
    local result
    result=$(pct exec "$LXC_ID" -- ping -c 2 -W 3 "$GATEWAY" 2>&1 | tail -1) || true
    echo "$result"
}

alert_via_telegram() {
    local message="$1"

    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return 0
    fi

    local now
    now=$(date +%s)
    local elapsed=$((now - LAST_ALERT_TIME))

    # Skip if we already alerted recently (cooldown)
    if [[ "$PREVIOUS_STATE" == "unhealthy" ]] && [[ "$elapsed" -lt "$STATE_COOLDOWN" ]]; then
        return 0
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

# ─── Main ─────────────────────────────────────────────────────────────────────

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

    # ── Attempt 1: curl from inside LXC ──────────────────────────────────────
    local http_code
    http_code=$(check_curl)
    local first_failed=false

    if [[ ! "$http_code" =~ ^[23][0-9]{2}$ ]]; then
        first_failed=true
    fi

    # ── Retry on first failure (catches brief glitches < RETRY_DELAY seconds)
    if [[ "$first_failed" == true ]]; then
        log_info "First attempt failed (HTTP $http_code), retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"

        http_code=$(check_curl)
        if [[ "$http_code" =~ ^[23][0-9]{2}$ ]]; then
            # Retry succeeded — brief transient, no alert needed
            CONSECUTIVE_FAILURES=0
            write_state "healthy"
            log_ok "LXC $LXC_ID internet OK after retry (HTTP $http_code) — transient glitch"
            exit 0
        fi
    fi

    # ── Connectivity Decision ────────────────────────────────────────────────

    if [[ "$http_code" =~ ^[23][0-9]{2}$ ]]; then
        # ── SUCCESS ──────────────────────────────────────────────────────────

        if [[ "$PREVIOUS_STATE" == "unhealthy" ]]; then
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

        CONSECUTIVE_FAILURES=0
        write_state "healthy"
        exit 0

    else
        # ── FAILURE ──────────────────────────────────────────────────────────

        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        log_warn "LXC $LXC_ID cannot reach $TEST_URL (HTTP $http_code, failure $CONSECUTIVE_FAILURES/$REQUIRED_FAILURES)"

        # Run diagnostic ping for alert context
        local diag
        diag=$(check_gateway_ping)
        log_info "Gateway ping result: $diag"

        if [[ "$CONSECUTIVE_FAILURES" -ge "$REQUIRED_FAILURES" ]]; then
            # ── Threshold reached — send alert ───────────────────────────────

            local alert_msg
            if [[ "$http_code" == "000" ]]; then
                alert_msg=$(cat <<-EOF
🚨 <b>LXC $LXC_ID Sin Internet</b>

<b>Detalle:</b> No se puede alcanzar $TEST_URL desde LXC $LXC_ID
<b>HTTP Code:</b> $http_code (timeout / sin conexión)
<b>Gateway ping:</b> $diag
<b>Host:</b> $(hostname -s)
<b>Hora:</b> $(date +'%Y-%m-%d %H:%M:%S')
<b>Fallos consecutivos:</b> $CONSECUTIVE_FAILURES

<b>Posibles causas:</b>
• Router bloqueó LXC por DoS Protection (EX520v)
• Firewall de Proxmox bloqueando salida
• Router sin NAT para $LXC_ID
• DNS no resuelve dentro del LXC

<b>Quick check:</b>
  ssh root@10.10.10.134 "pct exec $LXC_ID -- ping -c 2 10.10.10.1"
  ssh root@10.10.10.134 "pct exec $LXC_ID -- curl -s $TEST_URL"
EOF
)
            else
                alert_msg=$(cat <<-EOF
⚠️ <b>LXC $LXC_ID Internet Anómalo</b>

<b>Detalle:</b> HTTP $http_code al consultar $TEST_URL desde LXC $LXC_ID
<b>Gateway ping:</b> $diag
<b>Host:</b> $(hostname -s)
<b>Hora:</b> $(date +'%Y-%m-%d %H:%M:%S')
<b>Fallos consecutivos:</b> $CONSECUTIVE_FAILURES
EOF
)
            fi

            alert_via_telegram "$alert_msg" || true
            write_state "unhealthy"
            log_warn "ALERT: LXC $LXC_ID internet down (${CONSECUTIVE_FAILURES} consecutive failures)"
            exit 2

        else
            # ── Below threshold — log but don't alert yet ────────────────────

            local remaining=$((REQUIRED_FAILURES - CONSECUTIVE_FAILURES))
            log_warn "LXC $LXC_ID failure #$CONSECUTIVE_FAILURES — need $remaining more to alert"

            # Write state with incremented counter but keep PREVIOUS_STATE healthy
            # (we only transition to "unhealthy" when we actually alert)
            write_state "healthy"
            exit 0
        fi
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
