#!/bin/bash
# Jellyfin cache cleanup
# Removes transcode cache older than 3 days, metadata backups older than 30 days

LOG_FILE="/var/log/jellyfin-cleanup.log"
CACHE_DIR="/var/lib/jellyfin/data/transcodes"
METADATA_DIR="/var/lib/jellyfin/data/metadata"
CACHE_DAYS=3
METADATA_DAYS=30

echo "=== Jellyfin cleanup started at $(date) ===" >> "$LOG_FILE"

# Transcode cache
if [ -d "$CACHE_DIR" ]; then
  find "$CACHE_DIR" -type f -mtime +$CACHE_DAYS -delete 2>/dev/null
  find "$CACHE_DIR" -type d -empty -delete 2>/dev/null
  echo "Cleaned transcodes older than $CACHE_DAYS days" >> "$LOG_FILE"
fi

# Metadata backups (keep last 30 days)
if [ -d "$METADATA_DIR" ]; then
  find "$METADATA_DIR" -name "*.bak" -mtime +$METADATA_DAYS -delete 2>/dev/null
  echo "Cleaned metadata backups older than $METADATA_DAYS days" >> "$LOG_FILE"
fi

echo "=== Jellyfin cleanup completed at $(date) ===" >> "$LOG_FILE"