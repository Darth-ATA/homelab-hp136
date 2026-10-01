#!/bin/bash
# Deluge Restart for Ghost Space Recovery
# Checks for deleted-but-open files on torrents dataset and restarts deluge if found
# Runs weekly via cron

set -Eeuo pipefail

LOG_FILE="/var/log/deluge-ghost-space.log"
TORRENTS_MOUNT="/rpool/data/torrents"
DELUGE_CONTAINER="deluge"

echo "=== Deluge ghost space check started at $(date) ===" >> "$LOG_FILE"

# Check for deleted-but-open files on the torrents dataset
# Use lsof to find deleted files held open
deleted_open=$(lsof "$TORRENTS_MOUNT" 2>/dev/null | grep -c "deleted" || true)

if [[ "$deleted_open" -gt 0 ]]; then
    echo "Found $deleted_open deleted-but-open file handles on $TORRENTS_MOUNT" >> "$LOG_FILE"
    echo "Restarting $DELUGE_CONTAINER to release ghost space..." >> "$LOG_FILE"
    
    # Get space before restart
    space_before=$(zfs list -H -o used "$TORRENTS_MOUNT" 2>/dev/null | head -1)
    
    # Restart deluge container
    if docker restart "$DELUGE_CONTAINER" >> "$LOG_FILE" 2>&1; then
        echo "Deluge restarted successfully" >> "$LOG_FILE"
        sleep 3
        
        # Get space after restart
        space_after=$(zfs list -H -o used "$TORRENTS_MOUNT" 2>/dev/null | head -1)
        echo "Space before: $space_before, after: $space_after" >> "$LOG_FILE"
        
        # Check if space was recovered
        if [[ "$space_after" != "$space_before" ]]; then
            echo "Ghost space recovered!" >> "$LOG_FILE"
        fi
    else
        echo "ERROR: Failed to restart deluge" >> "$LOG_FILE"
        exit 1
    fi
else
    echo "No deleted-but-open files found. No action needed." >> "$LOG_FILE"
fi

echo "=== Deluge ghost space check completed at $(date) ===" >> "$LOG_FILE"