#!/usr/bin/env bash
# Usage: ./scripts/bazarr-download-remaining-subs.sh
#
# Downloads remaining Spanish subtitles for My Hero Academia S02 (episodes 21-25)
# via Bazarr API. These weren't auto-downloaded because provider daily limits
# (subdl, opensubtitlescom) were exceeded during the initial batch download.
#
# Run this after provider daily limits reset (usually within 24h).
set -euo pipefail

BAZARR_API="http://localhost:6767/api"
BAZARR_CONFIG="/root/docker/bazarr/config/config/config.yaml"

# Read auth token from Bazarr config at runtime (never hardcode secrets)
bazarr_token=$(python3 -c "
import yaml,sys
with open('$BAZARR_CONFIG') as f:
    cfg = yaml.safe_load(f)
print(cfg['auth']['apikey'])
" 2>/dev/null) || {
  echo "ERROR: Cannot read Bazarr auth token from $BAZARR_CONFIG"
  echo "Ensure the script runs inside LXC 101 and the config file exists."
  exit 1
}

# sonarrEpisodeId -> episode number mapping for remaining episodes
declare -A EPISODES=(
  [3996]=21
  [3997]=22
  [3998]=23
  [3999]=24
  [4000]=25
)

download_subtitle() {
  local episode_id=$1
  local ep_num=$2

  echo "=== Searching subtitles for S02E$(printf '%02d' "$ep_num") (id=$episode_id) ==="

  # Search available subtitles via providers
  search_result=$(curl -s -H "X-API-KEY: $bazarr_token" "$BAZARR_API/providers/episodes?episodeid=$episode_id")
  es_subs=$(echo "$search_result" | python3 -c "
import json,sys
data = json.load(sys.stdin).get('data', [])
esp = [s for s in data if s['language'] == 'es']
# Prefer opensubtitlescom (free), fallback to subdl
for s in esp:
    print(f\"{s['provider']}|{s['subtitle']}|{s['score']}\")
" 2>/dev/null)

  if [ -z "$es_subs" ]; then
    echo "  No Spanish subtitles found (providers may be rate-limited). Skipping."
    return 1
  fi

  # Try each Spanish subtitle option
  echo "$es_subs" | while IFS='|' read -r provider subtitle_id score; do
    echo "  Trying $provider (score=$score)..."

    download_code=$(curl -s -X POST \
      -H "X-API-KEY: $bazarr_token" \
      "$BAZARR_API/providers/episodes?seriesid=23&episodeid=$episode_id&hi=False&forced=False&original_format=False&provider=$provider&subtitle=$subtitle_id" \
      -w '%{http_code}' -o /dev/null)

    if [ "$download_code" = "204" ]; then
      echo "  ✓ Downloaded from $provider (score=$score)"
      return 0
    else
      echo "  ✗ $provider returned HTTP $download_code"
    fi
  done

  return 1
}

echo "Bazarr remaining subtitle downloader"
echo "===================================="
echo "Target: My Hero Academia S02 E21-E25"
echo ""
echo "Note: If all providers are rate-limited, the scheduled Bazarr search"
echo "will pick these up automatically when limits reset."
echo ""

success=0
failed=0

for id in "${!EPISODES[@]}"; do
  if download_subtitle "$id" "${EPISODES[$id]}"; then
    ((success++))
  else
    ((failed++))
  fi
  echo ""
done

echo "=== Summary ==="
echo "Downloaded: $success"
echo "Skipped: $failed"
echo ""
echo "Remaining episodes will be picked up by the next scheduled Bazarr search"
echo "(runs every $(grep wanted_search_frequency /root/docker/bazarr/config/config/config.yaml | grep -oP '[0-9]+') hours)."
