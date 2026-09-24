#!/usr/bin/env bash
# homelab-set-wake-alarm.sh — Calculate and set RTC wake alarm for 07:00 local (Europe/Madrid)
# Called by homelab-wake.service via systemd timer at 06:55 UTC daily
# Also called by homelab-suspend.sh before suspending

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────────
TIMEZONE="Europe/Madrid"
TARGET_HOUR_LOCAL=7   # 07:00 local Spain time (CET/CEST)
TARGET_MINUTE_LOCAL=0
RTC_DEVICE="/dev/rtc0"
LOG_TAG="homelab-wake"

# ─── Helpers ────────────────────────────────────────────────────────────────────
log() {
    local level="$1"
    shift
    logger -t "${LOG_TAG}" -p "user.${level}" "$*"
}

# ─── Main ───────────────────────────────────────────────────────────────────────
main() {
    log "info" "Calculating next 07:00 local (Europe/Madrid) wake alarm..."

    # Get current time in UTC (system clock)
    local now_utc
    now_utc="$(date -u +%s)"

    # Calculate target time: tomorrow 07:00 local = varies UTC depending on DST
    # Use date with TZ to compute the timestamp
    local target_utc
    local minute_fmt
    minute_fmt="$(printf '%02d' "${TARGET_MINUTE_LOCAL}")"
    target_utc="$(TZ="${TIMEZONE}" date -d "tomorrow ${TARGET_HOUR_LOCAL}:${minute_fmt}" +%s)"

    # Sanity check: target must be in the future (at least 1 hour, at most 30 hours)
    local diff=$((target_utc - now_utc))
    if (( diff < 3600 )) || (( diff > 108000 )); then
        log "err" "Calculated wake time looks wrong: diff=${diff}s (now=$(date -u -d @"${now_utc}"), target=$(date -u -d @"${target_utc}"))"
        exit 1
    fi

    log "info" "Setting RTC wake alarm for $(date -u -d @"${target_utc}" '+%Y-%m-%d %H:%M:%S UTC') (in $((diff/3600))h $((diff%3600/60))m)"

    # Clear any existing alarm first
    rtcwake -m disable -d "${RTC_DEVICE}" 2>/dev/null || true

    # Set the wake alarm (rtcwake -m no sets alarm without sleeping)
    # Use UTC timestamp since RTC typically runs in UTC
    if rtcwake -m no -d "${RTC_DEVICE}" -t "${target_utc}"; then
        log "info" "RTC wake alarm set successfully"
    else
        log "err" "Failed to set RTC wake alarm (exit code: $?)"
        exit 1
    fi

    # Verify alarm was set
    local alarm_set
    alarm_set="$(cat /sys/class/rtc/rtc0/wakealarm 2>/dev/null || echo "unknown")"
    log "info" "RTC wakealarm now: ${alarm_set}"
}

main "$@"