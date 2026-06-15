#!/bin/bash
# check-router-dns.sh — Monitor router DNS configuration
#
# Detects when the router's DHCP DNS setting changes away from AdGuard (192.168.1.2).
# This has happened twice before (May 2026, Jun 2026) — the DNS was silently
# set to 192.168.1.136 (a camera with no DNS server), breaking internet for
# all new WiFi clients.
#
# How it works:
#   1. Queries the router (192.168.1.1) as a DNS forwarder for google.com
#   2. If that fails, queries AdGuard directly (192.168.1.2) to distinguish
#      "router DNS is misconfigured" from "network is down"
#   3. Logs results and warns on misconfiguration
#
# Safe to run from cron. Idempotent.
#
# Cron example (hourly):
#   0 * * * * /usr/local/bin/check-router-dns.sh

set -Eeuo pipefail

# Ensure system commands are in PATH — cron has a minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ─── Configuration ────────────────────────────────────────────────────────────

ROUTER_DNS="192.168.1.1"
ADGUARD_DNS="192.168.1.2"
TEST_DOMAIN="google.com"
LOG_FILE="/var/log/check-router-dns.log"

# Telegram bot (empty = no alerts — set in host cron environment)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# State tracking (prevents alert spam)
STATE_FILE="${STATE_FILE:-/var/tmp/check-router-dns.state}"
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
    logger -t "check-router-dns" -- "WARN: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
    logger -t "check-router-dns" -- "ERROR: $*"
}

log_ok() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: $*" >> "$LOG_FILE"
}

# ─── Dependency Check ─────────────────────────────────────────────────────────

check_deps() {
    local -a missing=()

    for cmd in dig logger; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required commands: ${missing[*]}" >&2
        exit 1
    fi
}

# ─── DNS Query with Timeout ───────────────────────────────────────────────────

# Returns 0 and the resolved IP if successful, 1 on failure.
query_dns() {
    local -r server="$1"
    local -r domain="$2"

    dig "@$server" "$domain" +short +timeout=5 2>/dev/null || return 1
}

# ─── Main Check ───────────────────────────────────────────────────────────────

main() {
    # Restore previous state from disk
    read_state

    # Ensure log file exists and is writable
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot write to $LOG_FILE" >&2
        logger -t "check-router-dns" -- "ERROR: Cannot write to $LOG_FILE"
        exit 1
    }

    log_info "Checking router DNS configuration..."

    local router_result=""
    local adguard_result=""

    # Step 1: Query through the router
    router_result=$(query_dns "$ROUTER_DNS" "$TEST_DOMAIN") || true

    # Step 2: Query AdGuard directly as fallback
    adguard_result=$(query_dns "$ADGUARD_DNS" "$TEST_DOMAIN") || true

    # ─── Decision Logic ──────────────────────────────────────────────────────

    if [[ -n "$router_result" ]]; then
        # Router DNS works — everything is fine

        # Recover from previous unhealthy state
        if [[ "$PREVIOUS_STATE" == "unhealthy" ]]; then
            local recovery_msg
            recovery_msg=$(cat <<-EOF
✅ *Router DNS Restored*

Router DNS resolved $TEST_DOMAIN successfully
Host: $(hostname -s)
Time: $(date +'%Y-%m-%d %H:%M:%S')
EOF
)
            alert_via_telegram "$recovery_msg" || true
        fi

        write_state "healthy"
        log_ok "Router DNS ($ROUTER_DNS) resolved $TEST_DOMAIN → $router_result"
        log_ok "AdGuard DNS ($ADGUARD_DNS) resolved $TEST_DOMAIN → $adguard_result"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: Router DNS is working correctly"
        exit 0

    elif [[ -n "$adguard_result" ]]; then
        # Router DNS failed, but AdGuard works → router DNS is misconfigured
        local alert_msg
        alert_msg=$(cat <<-EOF
⚠️ *Router DNS Alert*

Issue: Router DNS misconfigured
Detail: $ROUTER_DNS failed to resolve $TEST_DOMAIN
  AdGuard at $ADGUARD_DNS resolves OK
  Router DNS likely set to incorrect upstream

Fix: Log into http://$ROUTER_DNS and set DNS to $ADGUARD_DNS
Host: $(hostname -s)
Time: $(date +'%Y-%m-%d %H:%M:%S')
EOF
)
        alert_via_telegram "$alert_msg" || true
        write_state "unhealthy"

        log_warn "Router DNS ($ROUTER_DNS) FAILED to resolve $TEST_DOMAIN"
        log_warn "AdGuard ($ADGUARD_DNS) resolves OK → $adguard_result"
        log_warn "Router DNS is likely set to an incorrect upstream (e.g. 192.168.1.136)"
        log_warn "Fix: Log into http://192.168.1.1 and set DNS to $ADGUARD_DNS"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: Router DNS is BROKEN — AdGuard works but router doesn't forward"
        exit 2

    else
        # Both failed — broader network issue
        local alert_msg
        alert_msg=$(cat <<-EOF
🚨 *Router DNS CRITICAL*

Issue: Both DNS resolvers unreachable
Detail: $ROUTER_DNS and $ADGUARD_DNS both failed to resolve $TEST_DOMAIN
  Possible causes: network down, AdGuard stopped, no internet

Host: $(hostname -s)
Time: $(date +'%Y-%m-%d %H:%M:%S')
EOF
)
        alert_via_telegram "$alert_msg" || true
        write_state "unhealthy"

        log_error "Both router ($ROUTER_DNS) and AdGuard ($ADGUARD_DNS) failed to resolve $TEST_DOMAIN"
        log_error "Possible causes: network down, AdGuard container stopped, no internet connectivity"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Network or DNS infrastructure issue — both resolvers unreachable"
        exit 3
    fi
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

check_deps
main "$@"
