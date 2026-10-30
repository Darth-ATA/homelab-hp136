# Download Pipeline Troubleshooting Guide

## Overview
This document covers common issues with the Sonarr → Prowlarr → Deluge download pipeline and their solutions.

## Infrastructure
- **Proxmox Host**: 10.10.10.134
- **Docker LXC**: 101 (10.10.10.142)
- **Prowlarr**: port 9696, API: `<your-prowlarr-api-key>`
- **Sonarr**: port 8989, API: `<your-sonarr-api-key>`
- **Deluge**: port 8112, password: `<your-deluge-password>`

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
scp docker/sonarr/compose.yml root@10.10.10.134:/tmp/
ssh root@10.10.10.134 "pct exec 101 -- mkdir -p /root/docker/sonarr"
ssh root@10.10.10.134 "pct push 101 /tmp/compose.yml /root/docker/sonarr/compose.yml"
ssh root@10.10.10.134 "pct exec 101 -- cd /root/docker/sonarr && docker compose up -d"
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
ssh root@10.10.10.134 "pct exec 101 -- sed -i 's|stream/movie/{{ .Query.IMDBID }}|stream/movie/tt{{ .Query.IMDBID }}|g' /config/custom/torrentio.yml"
ssh root@10.10.10.134 "pct exec 101 -- sed -i 's|/stream/series/{{ if .Query.IMDBID }}{{ .Query.IMDBID}}|stream/series/tt{{ if .Query.IMDBID }}{{ .Query.IMDBID}}|g' /config/custom/torrentio.yml"
ssh root@10.10.10.134 "pct exec 101 -- docker restart prowlarr"
```

### Test
```bash
# Test direct API call
curl -s "https://torrentio.strem.fun/providers=rarbg/stream/movie/tt8579674.json" | head -20
```

---

## Issue 4: Interactive Search Returns "Unable to load results"

### Symptoms
- Sonarr interactive search shows "Unable to load results for this episode search. Try again later"
- Backend API (`/api/v3/release?episodeId=...`) returns results, but UI doesn't display them

### Root Causes (found 2026-10-22)
1. **AnimeTosho indexer** (`feed.animetosho.org`) — DNS no longer resolves (NXDOMAIN). Prowlarr hangs trying to query it, causing the whole search request to timeout.
2. **Torrentio Proxy** — disabled by Prowlarr due to 429 (Too Many Requests) after recent failures. Sonarr still had it cached and kept getting 410 Gone.
3. **Sonarr SQLite "database is locked"** — concurrent writes (interactive search + RSS sync) caused lock contention, making searches fail.
4. **Deluge password mismatch** — Sonarr had a wrong Deluge password, causing "Unable to communicate with Deluge" errors that surfaced in the UI.

### Solution
1. Disable **AnimeTosho** in Prowlarr (and remove it from Sonarr's indexers).
2. Disable **Torrentio Proxy** in Prowlarr (and remove the duplicate from Sonarr).
3. Restart Sonarr to clear the SQLite lock and cached indexer state.
4. Fix the Deluge password in Sonarr to match Deluge's actual password (`deluge`).
5. Add working indexers with FlareSolverr: **1337x** (base URL `https://1337x.to/`, tag `flaresolverr`), **EZTV**, **The Pirate Bay**.

### Verify
```bash
# Sonarr API should return results
curl -s -H "X-Api-Key: <sonarr-api-key>" \
  "http://10.10.10.142:8989/api/v3/release?episodeId=<EPISODE_ID>" | jq length

# Prowlarr search should respond quickly
curl -s -H "X-Api-Key: <prowlarr-api-key>" \
  "http://10.10.10.142:9696/api/v1/search?query=My+Hero+Academia+S03E07" | head -c 100
```

### Notes
- If the UI still shows "Unable to load results" after the backend returns data, it's a frontend cache issue: hard-refresh (Ctrl+F5) or use incognito mode.
- Load average spikes (60+) on the LXC can cause Sonarr to crash (exit 137). Restart Sonarr if it becomes unresponsive.

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
curl -s -H "X-Api-Key: <your-sonarr-api-key>" \
  http://10.10.10.142:8989/api/v3/command \
  -X POST -H "Content-Type: application/json" \
  -d '{"name":"SeasonSearch","seriesId":<SERIES_ID>,"seasonId":<SEASON_ID>}'
```

### Verify Working
Check Sonarr logs:
```bash
ssh root@10.10.10.134 "pct exec 101 -- docker logs sonarr --tail 50 | grep -i 'download\|grab'"
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

## Issue 7: Torrentio Returns Results for Wrong Show (e.g., Dark instead of Akane-banashi)

### Symptoms
- Interactive Search in Sonarr returns results from Torrentio
- All results show metadata from a different show (e.g., Dark) regardless of what you're searching for
- Movie search returns Fight Club results regardless of the movie

### Cause
The Torrentio Cardigann definition file in Prowlarr (`/config/Definitions/Custom/torrentio.yml`) has **hardcoded IMDB IDs** instead of dynamic Go template variables:

```yaml
# ❌ WRONG — hardcoded, always returns Dark S1E1
path: ".../stream/series/tt5753856:1:1.json"
```

Prowlarr has both a simple static definition and a dynamic template-based one. The static one was in the active definition directory while the dynamic one sat unused.

### Solution
Replace the static definition with the dynamic template version:

```bash
# Inside Prowlarr container
docker exec prowlarr bash -c 'cp /config/custom/torrentio.yml /config/Definitions/Custom/torrentio.yml'
docker restart prowlarr
```

The dynamic version uses Go template variables that Prowlarr populates with the actual IMDB ID, season, and episode from Sonarr:

```yaml
# ✅ CORRECT — uses dynamic IMDB ID from Sonarr
path: ".../stream/series/tt{{ .Query.IMDBID }}:{{ .Query.Season }}:{{ .Query.Ep }}.json"
```

### Prevention (future deploys)
The compose file mounts `./custom/` to `/config/Definitions/Custom/` so the dynamic definition is always deployed in the right place.

### Verify
1. Go to Sonarr → any series → Interactive Search
2. Results should now match the selected series, not Dark/Fight Club
3. Check Prowlarr logs for torrentio requests with correct IMDB IDs

---

## Quick Diagnostic Commands

### Check Container Status
```bash
ssh root@10.10.10.134 "pct exec 101 -- docker ps"
```

### Check Sonarr Logs
```bash
ssh root@10.10.10.134 "pct exec 101 -- docker logs sonarr --tail 100"
```

### Check Prowlarr Logs
```bash
ssh root@10.10.10.134 "pct exec 101 -- docker logs prowlarr --tail 100"
```

### Test Deluge Connectivity
```bash
ssh root@10.10.10.134 "pct exec 101 -- docker exec deluge curl -s http://localhost:8112/json -u 'localclient:<your-deluge-password>' -d '{\"method\":\"daemon.get_config\",\"id\":1}'"
```

### Force Season Search via API
```bash
# Get series ID first
ssh root@10.10.10.134 "pct exec 101 -- docker exec sonarr sqlite3 /config/sonarr.db 'SELECT Id,Title FROM Series;'"

# Trigger search
ssh root@10.10.10.134 "pct exec 101 -- docker exec sonarr curl -s -H 'X-Api-Key: <your-sonarr-api-key>' 'http://localhost:8989/api/v3/command' -X POST -H 'Content-Type: application/json' -d '{\"name\":\"SeasonSearch\",\"seriesId\":<ID>,\"seasonId\":1}'"
```

---

## Related Files
- `docker/sonarr/compose.yml`
- `docker/radarr/compose.yml`
- `docker/prowlarr/compose.yml`
- `docker/prowlarr/custom/torrentio.yml` (dynamic Cardigann definition)
- `docker/deluge/compose.yml`
- `docker/jellyfin/compose.yml`
- Prowlarr Cardigann definitions: `/config/Definitions/Custom/` (inside container)

## References
- Prowlarr Indexers: https://github.com/dreulavelle/Prowlarr-Indexers
- TRaSH Guides: https://trash-guides.info/
