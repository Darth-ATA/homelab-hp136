#!/bin/bash
# ZFS Snapshot Pruning for rpool/data/media
# Keeps: last 7 daily, last 4 weekly, last 3 monthly snapshots
# Runs monthly via cron

set -Eeuo pipefail

LOG_FILE="/var/log/zfs-snapshot-prune.log"
POOL="rpool/data/media"
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=3

echo "=== ZFS snapshot pruning started at $(date) ===" >> "$LOG_FILE"

# List all snapshots for the pool, sorted by creation time (newest first)
# zfs list -t snapshot -o name,creation -r "$POOL" | grep "zfs-auto-snap" | sort -k2 -r

# Get all auto-snapshots for the pool
mapfile -t all_snaps < <(zfs list -t snapshot -H -o name -r "$POOL" 2>/dev/null | grep "zfs-auto-snap" || true)

if [[ ${#all_snaps[@]} -eq 0 ]]; then
    echo "No auto-snapshots found for $POOL" >> "$LOG_FILE"
    exit 0
fi

# Categorize snapshots by type and date
declare -A daily_snaps
declare -A weekly_snaps
declare -A monthly_snaps

for snap in "${all_snaps[@]}"; do
    # Extract date and type from snapshot name
    # Format: rpool/data/media@zfs-auto-snap_daily-2026-09-30-0425
    if [[ "$snap" =~ zfs-auto-snap_(daily|weekly|monthly)-([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        type="${BASH_REMATCH[1]}"
        date="${BASH_REMATCH[2]}"
        key="${type}-${date}"
        
        case "$type" in
            daily) daily_snaps["$key"]="$snap" ;;
            weekly) weekly_snaps["$key"]="$snap" ;;
            monthly) monthly_snaps["$key"]="$snap" ;;
        esac
    fi
done

# Sort dates (newest first) and keep only N newest
keep_snaps=()

# Keep daily
for key in $(printf '%s\n' "${!daily_snaps[@]}" | sort -r | head -"$KEEP_DAILY"); do
    keep_snaps+=("${daily_snaps[$key]}")
done

# Keep weekly
for key in $(printf '%s\n' "${!weekly_snaps[@]}" | sort -r | head -"$KEEP_WEEKLY"); do
    keep_snaps+=("${weekly_snaps[$key]}")
done

# Keep monthly
for key in $(printf '%s\n' "${!monthly_snaps[@]}" | sort -r | head -"$KEEP_MONTHLY"); do
    keep_snaps+=("${monthly_snaps[$key]}")
done

# Create a set of snaps to keep for fast lookup
declare -A keep_set
for snap in "${keep_snaps[@]}"; do
    keep_set["$snap"]=1
done

# Destroy snapshots not in keep set
destroyed=0
for snap in "${all_snaps[@]}"; do
    if [[ -z "${keep_set[$snap]:-}" ]]; then
        echo "Destroying snapshot: $snap" >> "$LOG_FILE"
        if zfs destroy "$snap" 2>/dev/null; then
            ((destroyed++))
        else
            echo "Failed to destroy: $snap" >> "$LOG_FILE"
        fi
    else
        echo "Keeping snapshot: $snap" >> "$LOG_FILE"
    fi
done

echo "=== ZFS snapshot pruning completed at $(date): $destroyed snapshots destroyed ===" >> "$LOG_FILE"