#!/bin/bash
# Soulseek cleanup for slskd/soularr
# Removes:
#   - /data/soulseek/incomplete/ older than 7 days
#   - /data/soulseek/failed_imports/ older than 14 days

LOG_FILE="/var/log/soulseek-cleanup.log"
INCOMPLETE_DIR="/data/soulseek/incomplete"
FAILED_DIR="/data/soulseek/failed_imports"
INCOMPLETE_DAYS=7
FAILED_DAYS=14

echo "=== Soulseek cleanup started at $(date) ===" >> "$LOG_FILE"

# Clean incomplete downloads (stuck > 7 days)
if [ -d "$INCOMPLETE_DIR" ]; then
  find "$INCOMPLETE_DIR" -type f -mtime +$INCOMPLETE_DAYS -print0 2>/dev/null | while IFS= read -r -d "" file; do
    echo "Removing incomplete: $file" >> "$LOG_FILE"
    rm -f "$file"
  done
  # Remove empty directories
  find "$INCOMPLETE_DIR" -type d -empty -delete 2>/dev/null
fi

# Clean failed imports (soularr gave up > 14 days)
if [ -d "$FAILED_DIR" ]; then
  find "$FAILED_DIR" -type f -mtime +$FAILED_DAYS -print0 2>/dev/null | while IFS= read -r -d "" file; do
    echo "Removing failed_import: $file" >> "$LOG_FILE"
    rm -f "$file"
  done
  # Remove empty directories
  find "$FAILED_DIR" -type d -empty -delete 2>/dev/null
fi

echo "=== Soulseek cleanup completed at $(date) ===" >> "$LOG_FILE"