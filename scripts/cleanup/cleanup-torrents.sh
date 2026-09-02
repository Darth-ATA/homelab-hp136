#!/bin/bash
# Torrent cleanup for Deluge
# Removes torrents matching ANY of:
#   - Seed ratio >= 2.0 (UL/DL)
#   - Size > 10 GB (downloaded size)
# Uses: deluge-console "del --remove_data <hash>"

LOG_FILE="/var/log/torrent-cleanup.log"
SEED_RATIO_THRESHOLD=2.0
SIZE_GB_THRESHOLD=10
DELUGE_USER="localclient"
# DELUGE_PASSWORD sourced from /root/.env (TELEGRAM_BOT_TOKEN style)
if [[ -f "/root/.env" ]]; then
    # shellcheck source=/dev/null
    source "/root/.env"
fi
DELUGE_PASSWORD="${DELUGE_PASSWORD:-}"

echo "=== Torrent cleanup started at $(date) ===" >> "$LOG_FILE"

# Get torrent list with basic info
# Format: [S] 100% Name hash
torrent_list=$(docker exec deluge deluge-console -U "$DELUGE_USER" -P "$DELUGE_PASSWORD" "info" 2>/dev/null)

if [ -z "$torrent_list" ]; then
  echo "No torrents found or deluge not responding" >> "$LOG_FILE"
  exit 0
fi

# Parse each line: [S] 100% Name hash
echo "$torrent_list" | while IFS= read -r line; do
  # Skip empty lines
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue

  # Extract hash (last field)
  hash=$(echo "$line" | awk '{print $NF}')
  [[ "$hash" =~ ^[a-f0-9]{40}$ ]] || continue

  # Get detailed info for this torrent
  details=$(docker exec deluge deluge-console -U "$DELUGE_USER" -P "$DELUGE_PASSWORD" "info $hash" 2>/dev/null)

  # Parse details - format:
  # [S] 100% Name hash
  #     DL: 67.1 G (0 B) UL: 132.3 G (108.1 G) ETA: -
  name=$(echo "$details" | head -1 | sed 's/^\[.\]  *[0-9]*% *//' | sed 's/ [a-f0-9]*$//')
  dl_line=$(echo "$details" | grep "DL:")
  
  # Extract downloaded and uploaded sizes
  # Format: DL: 67.1 G (0 B) UL: 132.3 G (108.1 G) ETA: -
  dl_gb=$(echo "$dl_line" | sed -n 's/.*DL: \([0-9.]*\) \([GMK]\) .*/\1/p' | head -1)
  dl_unit=$(echo "$dl_line" | sed -n 's/.*DL: [0-9.]* \([GMK]\) .*/\1/p' | head -1)
  ul_gb=$(echo "$dl_line" | sed -n 's/.*UL: \([0-9.]*\) \([GMK]\) .*/\1/p' | head -1)
  ul_unit=$(echo "$dl_line" | sed -n 's/.*UL: [0-9.]* \([GMK]\) .*/\1/p' | head -1)

  # Convert to GB for comparison using awk
  case "$dl_unit" in
    G) dl_gb_num="$dl_gb" ;;
    M) dl_gb_num=$(awk -v v="$dl_gb" 'BEGIN {print v/1024}') ;;
    K) dl_gb_num=$(awk -v v="$dl_gb" 'BEGIN {print v/1024/1024}') ;;
    *) dl_gb_num=0 ;;
  esac
  case "$ul_unit" in
    G) ul_gb_num="$ul_gb" ;;
    M) ul_gb_num=$(awk -v v="$ul_gb" 'BEGIN {print v/1024}') ;;
    K) ul_gb_num=$(awk -v v="$ul_gb" 'BEGIN {print v/1024/1024}') ;;
    *) ul_gb_num=0 ;;
  esac

  # Calculate ratio (UL/DL)
  ratio=$(awk -v ul="$ul_gb_num" -v dl="$dl_gb_num" 'BEGIN {if (dl > 0) print ul/dl; else print 0}')
  size_gb=$dl_gb_num

  should_remove=false
  reason=""

  # Check thresholds using awk for float comparison
  ratio_check=$(awk -v r="$ratio" -v t="$SEED_RATIO_THRESHOLD" 'BEGIN {print (r >= t) ? 1 : 0}')
  size_check=$(awk -v s="$size_gb" -v t="$SIZE_GB_THRESHOLD" 'BEGIN {print (s > t) ? 1 : 0}')

  if [ "$ratio_check" -eq 1 ]; then
    should_remove=true
    reason="ratio ${ratio} >= ${SEED_RATIO_THRESHOLD}"
  elif [ "$size_check" -eq 1 ]; then
    should_remove=true
    reason="size ${size_gb}GB > ${SIZE_GB_THRESHOLD}GB"
  fi

  if [ "$should_remove" = true ]; then
    echo "Removing: $name (hash: $hash) - $reason" >> "$LOG_FILE"
    docker exec deluge deluge-console -U "$DELUGE_USER" -P "$DELUGE_PASSWORD" "del --remove_data -c $hash" 2>/dev/null
  else
    echo "Keeping: $name (ratio: $ratio, size: ${size_gb}GB)" >> "$LOG_FILE"
  fi
done

echo "=== Torrent cleanup completed at $(date) ===" >> "$LOG_FILE"