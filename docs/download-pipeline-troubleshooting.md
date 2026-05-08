# Download Pipeline Troubleshooting Guide

## Overview
This document covers common issues with the Sonarr → Prowlarr → Deluge download pipeline and their solutions.

## Infrastructure
- **Proxmox Host**: 192.168.1.134
- **Docker LXC**: 101 (192.168.1.142)
- **Prowlarr**: port 9696, API: `e52b442319834cd7b1a4f8b3a37280d0`
- **Sonarr**: port 8989, API: `4ceaa8d5ea564ad4a6b37888b2ed76ee`
- **Deluge**: port 8112, password: `deluge`

---

## Issue 1: Sonarr/Radarr Can't See Downloads

### Symptoms
- Downloads complete in Deluge but don't appear in Sonarr/Radarr
- Queue stays empty despite active downloads

### Cause
Volume mount mismatch between Deluge and Sonarr/Radarr

### Solution
Update the volume mounts in the compose files:

**Sonarr** (`docker/sonarr/compose.yml`):
```yaml
volumes:
  - /data/media/tv:/tv
  - /data/torrents:/downloads   # NOT /data/torrents/tv
```

**Radarr** (`docker/radarr/compose.yml`):
```yaml
volumes:
  - /data/media/movies:/movies
  - /data/torrents:/downloads   # NOT /data/torrents/movies
```

### Apply Fix
```bash
# Copy updated compose to Proxmox and restart
scp docker/sonarr/compose.yml root@192.168.1.134:/tmp/
ssh root@192.168.1.134 "pct exec 101 -- mkdir -p /root/docker/sonarr"
ssh root@192.168.1.134 "pct push 101 /tmp/compose.yml /root/docker/sonarr/compose.yml"
ssh root@192.168.1.134 "pct exec 101 -- cd /root/docker/sonarr && docker compose up -d"
```

---

## Issue 2: Torrentio Indexer Returns No Results

### Symptoms
- Torrentio configured in Prowlarr but searches return nothing
- Stremio/Torrentio works but Prowlarr doesn't

### Cause
IMDB IDs missing 'tt' prefix in the custom YAML definition

### Solution
Edit `/config/custom/torrentio.yml` in the Prowlarr container:

**Find these lines:**
```yaml
path: ".../stream/movie/{{ .Query.IMDBID }}.json"
path: ".../stream/series/{{ if .Query.IMDBID }}{{ .Query.IMDBID}}..."
```

**Change to:**
```yaml
path: ".../stream/movie/tt{{ .Query.IMDBID }}.json"
path: ".../stream/series/tt{{ if .Query.IMDBID }}{{ .Query.IMDBID}}..."
```

### Apply Fix
```bash
# SSH to Proxmox and edit the file
ssh root@192.168.1.134 "pct exec 101 -- sed -i 's|stream/movie/{{ .Query.IMDBID }}|stream/movie/tt{{ .Query.IMDBID }}|g' /config/custom/torrentio.yml"
ssh root@192.168.1.134 "pct exec 101 -- sed -i 's|/stream/series/{{ if .Query.IMDBID }}{{ .Query.IMDBID}}|stream/series/tt{{ if .Query.IMDBID }}{{ .Query.IMDBID}}|g' /config/custom/torrentio.yml"
ssh root@192.168.1.134 "pct exec 101 -- docker restart prowlarr"
```

### Test
```bash
# Test direct API call
curl -s "https://torrentio.strem.fun/providers=rarbg/stream/movie/tt8579674.json" | head -20
```

---

## Issue 3: Sonarr Episode Search Crashes

### Symptoms
- Manual episode search fails with NullReferenceException
- Error in Sonarr logs: `EpisodeSearchService.cs:line 112`
- Series is newly added with no downloaded episodes

### Cause
Bug in Sonarr v4.0.17+ when searching new series without episodes

### Solution
Use **Season Search** instead of Episode Search:

1. Go to Sonarr → Series → Select the show
2. Click on the **Season** (not individual episode)
3. Use bulk action to "Search Selected"
4. Or trigger via API:
```bash
curl -s -H "X-Api-Key: 4ceaa8d5ea564ad4a6b37888b2ed76ee" \
  http://192.168.1.142:8989/api/v3/command \
  -X POST -H "Content-Type: application/json" \
  -d '{"name":"SeasonSearch","seriesId":<SERIES_ID>,"seasonId":<SEASON_ID>}'
```

### Verify Working
Check Sonarr logs:
```bash
ssh root@192.168.1.134 "pct exec 101 -- docker logs sonarr --tail 50 | grep -i 'download\|grab'"
```

---

## Issue 4: Content Not Available on Indexers

### Symptoms
- Searches work but return 0 results for specific shows
- Shows visible in Stremio but not in Prowlarr/Sonarr

### Cause
Content not available on configured public indexers

### Options
1. **Add Real-Debrid** - Configure RD API key in Torrentio settings for cached content
2. **Add TV-specific indexers** - TorrentGalaxy, LimeTorrents, RARBG
3. **Use private trackers** - Get access to private trackers with better content
4. **Wait** - Niche content may appear later on public trackers

### Configure Real-Debrid in Torrentio
1. Get API key from: https://real-debrid.com/account → API
2. Prowlarr → Settings → Indexers → Edit Torrentio
3. Add API key to "Debrid provider API Key" field
4. Set "Debrid provider" to "Real-Debrid"

---

## Issue 5: Rate Limiting (429 Errors)

### Symptoms
- Prowlarr logs show: "429 TooManyRequests"
- Indexers auto-disable for 3-5 minutes

### Solution
1. **Increase RSS sync interval** in Sonarr: Settings → Media Management → RSS Sync Interval (set to 30+ min)
2. **Disable auto-search** on problematic indexers in Prowlarr
3. **Remove failing indexers** - 1337x blocked by CloudFlare, Internet Archive times out

---

## Issue 6: Jellyfin Shows Empty Libraries

### Symptoms
- Movies and TV show folders show 0 items in Jellyfin
- Media files exist in /data/media/

### Cause
- Mount was read-only (:ro) instead of read-write (:rw)
- Libraries haven't been scanned after initial setup

### Solution
1. Fix the mount in compose file - change :ro to :rw:
   ```yaml
   - /data/media:/media:rw   # NOT :ro
   ```

2. Apply fix and restart:
   ```bash
   sed -i 's|:/media:ro|:/media:rw|' /path/to/compose.yml
   docker compose up -d --force-recreate
   ```

3. Trigger library scan in Jellyfin UI:
   - Dashboard → Scheduled Tasks → Scan Media Library → Run
   - Or click the refresh icon on library cards

---

## Quick Diagnostic Commands

### Check Container Status
```bash
ssh root@192.168.1.134 "pct exec 101 -- docker ps"
```

### Check Sonarr Logs
```bash
ssh root@192.168.1.134 "pct exec 101 -- docker logs sonarr --tail 100"
```

### Check Prowlarr Logs
```bash
ssh root@192.168.1.134 "pct exec 101 -- docker logs prowlarr --tail 100"
```

### Test Deluge Connectivity
```bash
ssh root@192.168.1.134 "pct exec 101 -- docker exec deluge curl -s http://localhost:8112/json -u 'localclient:deluge' -d '{\"method\":\"daemon.get_config\",\"id\":1}'"
```

### Force Season Search via API
```bash
# Get series ID first
ssh root@192.168.1.134 "pct exec 101 -- docker exec sonarr sqlite3 /config/sonarr.db 'SELECT Id,Title FROM Series;'"

# Trigger search
ssh root@192.168.1.134 "pct exec 101 -- docker exec sonarr curl -s -H 'X-Api-Key: 4ceaa8d5ea564ad4a6b37888b2ed76ee' 'http://localhost:8989/api/v3/command' -X POST -H 'Content-Type: application/json' -d '{\"name\":\"SeasonSearch\",\"seriesId\":<ID>,\"seasonId\":1}'"
```

---

## Related Files
- `docker/sonarr/compose.yml`
- `docker/radarr/compose.yml`
- `docker/prowlarr/compose.yml`
- `docker/deluge/compose.yml`
- `docker/jellyfin/compose.yml`
- Prowlarr config: `/config/custom/torrentio.yml` (inside container 101)

## References
- Prowlarr Indexers: https://github.com/dreulavelle/Prowlarr-Indexers
- TRaSH Guides: https://trash-guides.info/
