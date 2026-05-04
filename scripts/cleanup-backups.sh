#!/bin/bash
# Cleanup script for Proxmox backups
# Retention: Keep daily backups, but for previous months only keep the last backup

CURRENT_YEAR_MONTH=$(date +%Y-%m)
LOG_FILE="/var/log/backup-cleanup.log"

echo "Backup cleanup started at $(date)" >> $LOG_FILE

# Process each storage path
for STORAGE_PATH in "/var/lib/vz/dump" "/var/lib/vz/snapshot"; do
  if [ ! -d "$STORAGE_PATH" ]; then
    continue
  fi
  
  echo "Processing: $STORAGE_PATH" >> $LOG_FILE
  
  # Create temp file for processing
  > /tmp/backup_files.txt
  
  # Find all backup files
  find "$STORAGE_PATH" -name "vzdump-*.vma.*" -type f 2>/dev/null | while read -r backup_file; do
    filename=$(basename "$backup_file")
    
    # Extract date from filename: vzdump-qemu-100-2026_04_15-21_00_02.vma.zst
    if [[ "$filename" =~ vzdump-(qemu|lxc)-([0-9]+)-([0-9]{4})_([0-9]{2})_([0-9]{2})-([0-9]{2})_([0-9]{2})\. ]]; then
      year="${BASH_REMATCH[3]}"
      month="${BASH_REMATCH[4]}"
      day="${BASH_REMATCH[5]}"
      file_year_month="$year-$month"
      file_date="$year-$month-$day"
      
      # Store: year-month, full-date, filepath
      echo "$file_year_month $file_date $backup_file" >> /tmp/backup_files.txt
    fi
  done
  
  # Process files by year-month
  if [ -f /tmp/backup_files.txt ]; then
    # Get unique year-months
    awk '{print $1}' /tmp/backup_files.txt | sort -u | while read -r ym; do
      if [ "$ym" = "$CURRENT_YEAR_MONTH" ]; then
        # Current month: keep all
        echo "Keeping all backups from current month: $ym" >> $LOG_FILE
      else
        # Previous month(s): keep only the last one
        # Get all files for this year-month, sorted by date (newest last)
        grep "^$ym " /tmp/backup_files.txt | sort -k2 -r > /tmp/files_for_month.txt
        
        # Skip the first one (newest), delete the rest
        tail -n +2 /tmp/files_for_month.txt | while read -r line; do
          file_to_delete=$(echo $line | awk '{print $3}')
          if [ -f "$file_to_delete" ]; then
            echo "Deleting: $file_to_delete" >> $LOG_FILE
            rm -f "$file_to_delete"
            # Also delete associated .log and .notes files
            rm -f "${file_to_delete%.*}.log" "${file_to_delete%.*}.notes"
          fi
        done
        rm -f /tmp/files_for_month.txt
      fi
    done
    
    rm -f /tmp/backup_files.txt
  fi
done

echo "Backup cleanup completed at $(date)" >> $LOG_FILE
