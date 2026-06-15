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

# ─── Configuration ────────────────────────────────────────────────────────────

ROUTER_DNS="192.168.1.1"
ADGUARD_DNS="192.168.1.2"
TEST_DOMAIN="google.com"
LOG_FILE="/var/log/check-router-dns.log"

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
        log_ok "Router DNS ($ROUTER_DNS) resolved $TEST_DOMAIN → $router_result"
        log_ok "AdGuard DNS ($ADGUARD_DNS) resolved $TEST_DOMAIN → $adguard_result"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] OK: Router DNS is working correctly"
        exit 0

    elif [[ -n "$adguard_result" ]]; then
        # Router DNS failed, but AdGuard works → router DNS is misconfigured
        log_warn "Router DNS ($ROUTER_DNS) FAILED to resolve $TEST_DOMAIN"
        log_warn "AdGuard ($ADGUARD_DNS) resolves OK → $adguard_result"
        log_warn "Router DNS is likely set to an incorrect upstream (e.g. 192.168.1.136)"
        log_warn "Fix: Log into http://192.168.1.1 and set DNS to $ADGUARD_DNS"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: Router DNS is BROKEN — AdGuard works but router doesn't forward"
        exit 2

    else
        # Both failed — broader network issue
        log_error "Both router ($ROUTER_DNS) and AdGuard ($ADGUARD_DNS) failed to resolve $TEST_DOMAIN"
        log_error "Possible causes: network down, AdGuard container stopped, no internet connectivity"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Network or DNS infrastructure issue — both resolvers unreachable"
        exit 3
    fi
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

check_deps
main "$@"
