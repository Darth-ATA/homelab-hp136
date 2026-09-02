#!/bin/bash
# Backup cleanup — Retention: 7 daily + 6 monthly
# Runs daily at 01:00 and 05:00 via cron

LOG_FILE="/var/log/backup-cleanup.log"
BACKUP_DIR="/var/lib/vz/dump"

echo "=== Backup cleanup started at $(date) ===" >> "$LOG_FILE"

# Process each VM/CT backup group
for backup_prefix in vzdump-qemu-100 vzdump-lxc-101 vzdump-lxc-102 vzdump-lxc-103 vzdump-lxc-104 vzdump-lxc-105; do
  echo "Processing: $backup_prefix" >> "$LOG_FILE"

  # Find all backup files for this VM/CT (newest first)
  mapfile -t files < <(find "$BACKUP_DIR" -name "${backup_prefix}-*.vma*" -o -name "${backup_prefix}-*.tar*" 2>/dev/null | sort -r)

  if [ ${#files[@]} -eq 0 ]; then
    continue
  fi

  # Separate by date (extract YYYY-MM-DD from filename)
  declare -A daily_files
  declare -A monthly_files

  for f in "${files[@]}"; do
    fname=$(basename "$f")
    # Extract date: vzdump-qemu-100-2026_08_31-21_00_06.vma.zst
    if [[ "$fname" =~ ${backup_prefix}-([0-9]{4})_([0-9]{2})_([0-9]{2})- ]]; then
      y="${BASH_REMATCH[1]}"
      m="${BASH_REMATCH[2]}"
      d="${BASH_REMATCH[3]}"
      date_key="$y-$m-$d"
      month_key="$y-$m"

      # Keep newest per day
      if [[ -z "${daily_files[$date_key]:-}" ]]; then
        daily_files[$date_key]="$f"
      fi
      # Keep newest per month
      if [[ -z "${monthly_files[$month_key]:-}" ]]; then
        monthly_files[$month_key]="$f"
      fi
    fi
  done

  # Determine which files to KEEP
  declare -A keep_files

  # Keep last 7 daily backups
  count=0
  for date_key in $(printf '%s\n' "${!daily_files[@]}" | sort -r); do
    if [ $count -lt 7 ]; then
      keep_files["${daily_files[$date_key]}"]=1
      ((count++))
    fi
  done

  # Keep last 6 monthly backups (excluding current month if already covered by daily)
  count=0
  for month_key in $(printf '%s\n' "${!monthly_files[@]}" | sort -r); do
    if [ $count -lt 6 ]; then
      keep_files["${monthly_files[$month_key]}"]=1
      ((count++))
    fi
  done

  # Delete files NOT in keep list
  for f in "${files[@]}"; do
    if [[ -z "${keep_files[$f]:-}" ]]; then
      echo "Deleting: $f" >> "$LOG_FILE"
      rm -f "$f"
      # Also remove associated .log and .notes files
      base="${f%.*}"
      rm -f "${base}.log" "${base}.notes"
    fi
  done
done

echo "=== Backup cleanup completed at $(date) ===" >> "$LOG_FILE"