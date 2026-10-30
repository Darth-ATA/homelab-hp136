# Design: Soularr Integration

## Executive Summary

Deploy two Docker containers (slskd + soularr) on LXC 101 to bridge Lidarr with the Soulseek P2P network, giving Lidarr access to music not available on public torrent trackers. slskd acts as the Soulseek daemon (web UI on 5030, P2P on 50300). soularr is a Python script that polls Lidarr's wanted list every 5 minutes, searches Soulseek via slskd's API, downloads matches, and triggers Lidarr import. Both containers share a dedicated Docker network (`soularrnet`), mount the existing `/data` volume for download access, and are managed under Arcane alongside the existing `arrsuite` stack.

**Key design decisions:**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Network isolation | Shared `soularrnet` bridge | soularr resolves slskd by container hostname; consistent with deluge+bazarr pattern |
| User runtime | `user: 1000:1000` + PUID/PGID env | Neither is a linuxserver image; `user:` is Docker-native, env vars satisfy project convention |
| Download storage | `/data/soulseek/` subdir under single `/data` mount | Lidarr sees it at `/data/soulseek/` for import; hardlinks work within the single mount |
| Lidarr import flow | soularr API call (not download client) | No change to Deluge as download client; soularr uses Lidarr API to trigger import |
| Release selection | `use_selected_lidarr_release = True` | Uses Lidarr's own interactive search results — more reliable than soularr's matching |

---

## 1. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  LXC 101 - 192.168.1.142                                             │
│                                                                      │
│  ┌──────────────────────────────────┐  ┌──────────────────────────┐  │
│  │  Lidarr Container                │  │  Lidarr API: 8686        │  │
│  │  lidarr_default network          │  │                          │  │
│  │  Mount: /data → /data (ZFS)      │  │  Wanted, Import          │  │
│  └──────────┬───────────────────────┘  └──────────┬───────────────┘  │
│             │                                     │                   │
│             │ same /data mount                    │ HTTP              │
│             ▼                                     ▼                   │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │  /data/soulseek/downloads/     (host path)                   │     │
│  │  └── Artist/Album/track.flac                                 │     │
│  └─────────────────────────────────────────────────────────────┘     │
│             ▲                          ▲                              │
│             │ mounts /data             │ mounts /data/soulseek/       │
│             │                          │                              │
│  ┌──────────────────────┐  ┌──────────────────────────┐              │
│  │  slskd Container     │  │  soularr Container       │              │
│  │  Port: 5030 (UI)     │  │  Port: 8265 (WebUI)      │              │
│  │  Port: 50300 (P2P)   │  │  User: 1000:1000         │              │
│  │  User: 1000:1000     │  │  Interval: 300s          │              │
│  │  Config: slskd.yml   │  │  Config: config.ini      │              │
│  └──────────┬───────────┘  └───────────┬──────────────┘              │
│             │                           │                             │
│             └──────────┬────────────────┘                             │
│                        │                                              │
│             ┌──────────▼───────────┐                                  │
│             │ soularrnet (bridge)   │                                  │
│             │ slskd:5030            │                                  │
│             │ soularr → slskd API   │                                  │
│             └──────────────────────┘                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ P2P port 50300
                              ▼
                    ┌──────────────────┐
                    │  Internet        │
                    │  Soulseek P2P    │
                    │  Network         │
                    └──────────────────┘
```

### Data Flow

```
1. soularr ──GET──→ Lidarr API (8686)        → Wanted album list
2. soularr ──POST─→ slskd API (5030)         → Search Soulseek
3. slskd    ──P2P──→ Soulseek Network (50300) → Find files
4. slskd    ──write→ /data/soulseek/downloads → Save files
5. soularr  ──poll─→ /data/soulseek/downloads → Detect completion
6. soularr  ──POST─→ Lidarr API (8686)        → Trigger import
7. Lidarr   ──read─→ /data/soulseek/downloads → Read files
8. Lidarr   ──link─→ /data/media/music/       → Final library
```

---

## 2. Component Design

### 2.1 Container Definitions

#### slskd — Reference Compose

Location (repo): `docker/slskd/compose.yml`
Location (LXC): `/root/docker/arcane/data/projects/slskd/compose.yaml`

```yaml
services:
  slskd:
    image: ghcr.io/slskd/slskd:latest
    container_name: slskd
    hostname: slskd
    user: "1000:1000"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Madrid
      - SLSKD_REMOTE_CONFIGURATION=false
      - SLSKD_API_KEY=${SLSKD_API_KEY}
    ports:
      - "5030:5030"    # Web UI (HTTP)
      - "50300:50300"  # Soulseek P2P
    volumes:
      - /root/docker/slskd/config:/app
      - /data:/data
    restart: unless-stopped

networks:
  default:
    name: soularrnet
```

**Notes:**
- `SLSKD_REMOTE_CONFIGURATION=false` — config is file-based, no runtime edits via UI
- `SLSKD_API_KEY` — passed via environment; primary admin key for soularr auth
- Port 5031 (HTTPS) deliberately excluded — not needed behind local network
- Container runs as UID/GID 1000 so downloaded files match the `arrsuite` user

#### soularr — Reference Compose

Location (repo): `docker/soularr/compose.yml`
Location (LXC): `/root/docker/arcane/data/projects/soularr/compose.yaml`

```yaml
services:
  soularr:
    image: mrusse08/soularr:latest
    container_name: soularr
    hostname: soularr
    user: "1000:1000"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Madrid
      - SCRIPT_INTERVAL=300
      - WEBUI_ENABLED=true
    ports:
      - "8265:8265"    # Web UI (dashboard + log viewer)
    volumes:
      - /root/docker/soularr/config:/data
      - /data/soulseek/downloads:/downloads
    restart: unless-stopped

networks:
  default:
    name: soularrnet
```

**Notes:**
- `SCRIPT_INTERVAL=300` — polls Lidarr wanted list every 5 minutes
- `WEBUI_ENABLED=true` — enables the built-in dashboard at port 8265
- Config at `/data/config.ini` (mapped from `/root/docker/soularr/config/`)
- Download mount: `/data/soulseek/downloads:/downloads` — same physical path as slskd's download dir

### 2.2 Configuration Files

#### slskd.yml

Location (repo): `docker/slskd/slskd.yml`
Location (LXC): `/root/docker/slskd/config/slskd.yml`

```yaml
###############################################################################
# slskd configuration
# See: https://github.com/slskd/slskd/blob/master/docs/config.md
# Full example: https://github.com/slskd/slskd/blob/master/config/slskd.example.yml
###############################################################################

soulseek:
  username: ""              # Set via SLSKD_API_KEY env var? No — username/password
  password: ""              # REQUIRED: Fill in your Soulseek credentials
  listen_port: 50300

directories:
  downloads: /data/soulseek/downloads
  incomplete: /data/soulseek/incomplete

web:
  authentication:
    disabled: false
    username: slskd
    password: slskd
    jwt:
      ttl: 604800000  # 7 days
  # Primary API key set via SLSKD_API_KEY environment variable
  # Additional keys can be added here if needed:
  # api_keys:
  #   soularr:
  #     key: "your-16-to-255-char-key"
  #     role: administrator
  #     cidr: 0.0.0.0/0,::/0

retention:
  searches: 10080       # 7 days
  downloads:
    succeeded: 1440     # 1 day
    errored: 20160      # 2 weeks
    cancelled: 30       # 30 minutes
```

**Deployment note:** The user MUST create a free Soulseek account at https://www.slsknet.org/ and fill in the `soulseek.username` and `soulseek.password` fields before starting the container.

#### config.ini (soularr)

Location (repo): `docker/soularr/config.ini`
Location (LXC): `/root/docker/soularr/config/config.ini`

```ini
[Lidarr]
; Get from Lidarr: Settings > General > Security > API Key
api_key = LIDARR_API_KEY_GOES_HERE
; Use the host IP since Lidarr is on its own Docker network
host_url = http://192.168.1.142:8686
; Path inside Lidarr container (it has /data:/data mount)
download_dir = /data/soulseek/downloads
; Let soularr trigger Lidarr import after download
disable_sync = False

[Slskd]
; Must match the SLSKD_API_KEY env var value
api_key = SLSKD_API_KEY_GOES_HERE
; Container hostname resolves via soularrnet bridge network
host_url = http://slskd:5030
url_base = /
; Path inside slskd container (matches slskd.yml directories.downloads)
download_dir = /downloads
delete_searches = False
stalled_timeout = 3600
remote_queue_timeout = 300

[Release Settings]
; Use the release the user selected in Lidarr's interactive search
use_selected_lidarr_release = True
; Pick the release with the most common track count
use_most_common_tracknum = True
allow_multi_disc = True
accepted_countries = Europe,Japan,United Kingdom,United States,[Worldwide],Australia,Canada
skip_region_check = False
accepted_formats = CD,Digital Media,Vinyl

[Search Settings]
search_timeout = 5000
maximum_peer_queue = 50
minimum_peer_upload_speed = 0
minimum_filename_match_ratio = 0.8
minimum_search_interval = 5
; Preferred file types — prefer lossless, fallback to high-bitrate MP3
allowed_filetypes = flac 24/192,flac 16/44.1,flac,mp3 320,mp3
ignored_users =
; Don't prepend artist to album searches (Soulseek naming varies)
album_prepend_artist = False
track_prepend_artist = True
; Start with first page, increment on each run
search_type = incrementing_page
; Max albums to grab per run
number_of_albums_to_grab = 10
title_blacklist =
search_blacklist =
; Only search for albums Lidarr reports as "missing"
search_source = missing
; Denylist albums that failed import to avoid re-download loops
failed_import_denylist = True

[Download Settings]
download_filtering = True
use_extension_whitelist = False
extensions_whitelist = lrc,nfo,txt

[Logging]
level = INFO
format = [%(levelname)s|%(module)s|L%(lineno)d] %(asctime)s: %(message)s
datefmt = %Y-%m-%dT%H:%M:%S%z
log_to_file = True
log_file = soularr.log
max_bytes = 1048576
backup_count = 3
```

### 2.3 Volume Mounts & Storage Layout

```
Host (Proxmox LXC 101)           Container mounts
─────────────────────────────    ──────────────────────────────────
/data/                            Lidarr:   /data → /data
├── media/                        Radarr:   /data → /data
│   ├── movies/                   Sonarr:   /data → /data
│   ├── tv/                       slskd:    /data → /data
│   └── music/  ← Lidarr lib     soularr:  /data/soulseek/downloads → /downloads
├── torrents/
│   ├── movies/
│   ├── tv/
│   └── music/
└── soulseek/                     (NEW)
    ├── incomplete/                slskd incomplete downloads
    └── downloads/                 slskd completed → soularr watches → Lidarr imports
        └── Artist/
            └── Album/
                └── track.flac

Config dirs (host):
/root/docker/
├── slskd/
│   └── config/
│       └── slskd.yml
└── soularr/
    └── config/
        └── config.ini
```

**Mount rationale:**

| Container | Mount | Purpose |
|-----------|-------|---------|
| slskd | `/root/docker/slskd/config:/app` | App data + `slskd.yml` config |
| slskd | `/data:/data` | Downloads land at `/data/soulseek/downloads/` (visible to Lidarr) |
| soularr | `/root/docker/soularr/config:/data` | Config.ini at `/data/config.ini` |
| soularr | `/data/soulseek/downloads:/downloads` | Watch directory; same files slskd writes |
| Lidarr | `/data:/data` (existing) | Reads `/data/soulseek/downloads/` for import |

**Why this works:**
- slskd writes to `/data/soulseek/downloads/` inside its container → host `/data/soulseek/downloads/`
- soularr has the same host path mounted as `/downloads` → watches for completion
- Lidarr has `/data` mounted → sees `/data/soulseek/downloads/` → imports to `/data/media/music/`
- All paths are under the single ZFS mount (`/data`) → hardlinks work inside Lidarr's container

---

## 3. Network Topology

| Container | Network | Reachable at | Notes |
|-----------|---------|-------------|-------|
| slskd | `soularrnet` | `slskd:5030`, `192.168.1.142:5030`, `192.168.1.142:50300` | P2P port exposed on host |
| soularr | `soularrnet` | `192.168.1.142:8265` | Web UI only on host (no P2P) |
| Lidarr | `lidarr_default` | `192.168.1.142:8686` | Existing, separate network |

**Container resolution within `soularrnet`:**
- soularr resolves `slskd:5030` via Docker DNS (same bridge network)
- soularr reaches Lidarr via `192.168.1.142:8686` (host IP — cross-network)

**Port forwarding (router):** Not configured. slskd operates in outbound-only mode — it can initiate connections to Soulseek peers but won't accept incoming ones. This reduces the peer pool but is fully functional for downloading music.

**LXC 101 firewall:**
- Port 5030: local access only (LAN)
- Port 8265: local access only (LAN)
- Port 50300: optionally exposed for LAN P2P (no WAN ingress)

---

## 4. Lidarr Integration Points

### No changes to Lidarr itself

The existing Lidarr container composition, configuration, download client (Deluge), and root folder (`/data/media/music`) remain unchanged. No additional Lidarr configuration is required beyond noting the API key.

### soularr interaction with Lidarr API

soularr uses these Lidarr API endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/wanted/missing` | GET | Fetch wanted albums (`search_source = missing`) |
| `/api/v1/album/{id}` | GET | Get album details for search |
| `/api/v1/command` | POST | Trigger download/import (`DownloadAlbum` command) |
| `/api/v1/queue` | GET | Check import queue status |

### Import Flow Detail

```
soularr              slskd               Lidarr               Filesystem
───────              ─────               ──────               ──────────
  │                    │                   │                    │
  │──GET /wanted──────>│                   │                    │
  │<──album list───────│                   │                    │
  │                    │                   │                    │
  │──POST search──────>│                   │                    │
  │<──results──────────│                   │                    │
  │                    │                   │                    │
  │──POST download────>│                   │                    │
  │                    │──P2P fetch───────>│                    │
  │                    │                   │                    │
  │                    │                   │              write │
  │                    │                   │         /data/     │
  │                    │                   │    soulseek/       │
  │                    │                   │    downloads/      │
  │                    │                   │      Artist/       │
  │                    │                   │      Album/        │
  │                    │                   │      track.flac    │
  │                    │                   │                    │
  │──poll /downloads──>│                   │                    │
  │  file detected     │                   │                    │
  │                    │                   │                    │
  │──POST /command────>│                   │                    │
  │  (trigger import)  │                   │                    │
  │                    │              read │                    │
  │                    │  /data/soulseek/  │                    │
  │                    │                   │              link  │
  │                    │                   │         /data/     │
  │                    │                   │         media/     │
  │                    │                   │         music/     │
  │                    │                   │         Artist/    │
  │                    │                   │         Album/     │
  │                    │                   │         track.flac │
```

**Hardlink benefit:** Since both source (`/data/soulseek/downloads/`) and destination (`/data/media/music/`) share the same `/data` mount inside Lidarr's container, Lidarr can hardlink instead of copy — saving storage space.

---

## 5. Arcane Project Configuration

Two Arcane projects are created under `/root/docker/arcane/data/projects/`:

### Project: slskd

```
/root/docker/arcane/data/projects/slskd/
├── compose.yaml    # (same as compose.yml reference copy)
└── .env            # Contains SLSKD_API_KEY
```

**.env file** (NEVER committed):
```env
SLSKD_API_KEY=<generated-64-char-hex-string>
```

### Project: soularr

```
/root/docker/arcane/data/projects/soularr/
├── compose.yaml    # (same as compose.yml reference copy)
└── .env            # Empty (all secrets in config.ini)
```

**.env file:**
```env
# No secrets needed here — keys are in config.ini
```

**Arcane UI steps:**
1. Open Arcane at http://192.168.1.142:3552
2. Add Project → `/root/docker/arcane/data/projects/slskd/`
3. Add Project → `/root/docker/arcane/data/projects/soularr/`
4. Deploy both projects

---

## 6. Deployment Procedure

### Phase 1: Prerequisites

```bash
# 1. Create Soulseek account
#    Visit https://www.slsknet.org/ and register
#    Save username + password

# 2. Get Lidarr API key
#    Open Lidarr UI → Settings → General → Security → API Key
#    Copy the key (will go in config.ini)
```

### Phase 2: Directory Setup on LXC 101

```bash
# SSH into Proxmox host, then LXC 101
ssh -i ~/.ssh/homelab_key root@192.168.1.134

# Enter container
pct enter 101

# Create directory structure
mkdir -p /root/docker/slskd/config
mkdir -p /root/docker/soularr/config
mkdir -p /data/soulseek/{incomplete,downloads}

# Set ownership
chown -R 1000:1000 /root/docker/slskd
chown -R 1000:1000 /root/docker/soularr
chown -R 1000:1000 /data/soulseek
```

### Phase 3: Write Configuration Files

```bash
# Write slskd.yml (see section 2.2 for exact content)
cat > /root/docker/slskd/config/slskd.yml << 'SLSKD_EOF'
... paste slskd.yml content here, fill in Soulseek credentials ...
SLSKD_EOF

# Write config.ini (see section 2.2 for exact content)
cat > /root/docker/soularr/config/config.ini << 'SOULARR_EOF'
... paste config.ini content here, fill in both API keys ...
SOULARR_EOF

# Generate a random API key for slskd (64 hex chars)
SLSKD_API_KEY=$(openssl rand -hex 32)
echo "SLSKD_API_KEY=$SLSKD_API_KEY"
```

### Phase 4: Create Arcane Project Files

```bash
# Write slskd compose.yaml and .env
cat > /root/docker/arcane/data/projects/slskd/compose.yaml << 'EOF'
services:
  slskd:
    image: ghcr.io/slskd/slskd:latest
    container_name: slskd
    hostname: slskd
    user: "1000:1000"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Madrid
      - SLSKD_REMOTE_CONFIGURATION=false
      - SLSKD_API_KEY=${SLSKD_API_KEY}
    ports:
      - "5030:5030"
      - "50300:50300"
    volumes:
      - /root/docker/slskd/config:/app
      - /data:/data
    restart: unless-stopped

networks:
  default:
    name: soularrnet
EOF

echo "SLSKD_API_KEY=$SLSKD_API_KEY" > /root/docker/arcane/data/projects/slskd/.env

# Write soularr compose.yaml
cat > /root/docker/arcane/data/projects/soularr/compose.yaml << 'EOF'
services:
  soularr:
    image: mrusse08/soularr:latest
    container_name: soularr
    hostname: soularr
    user: "1000:1000"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Madrid
      - SCRIPT_INTERVAL=300
      - WEBUI_ENABLED=true
    ports:
      - "8265:8265"
    volumes:
      - /root/docker/soularr/config:/data
      - /data/soulseek/downloads:/downloads
    restart: unless-stopped

networks:
  default:
    name: soularrnet
EOF

touch /root/docker/arcane/data/projects/soularr/.env
```

### Phase 5: Deploy via Arcane

```bash
# Exit container
exit

# From Proxmox host, deploy via Arcane
ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- curl -X POST http://localhost:3552/api/projects \
    -H 'Content-Type: application/json' \
    -d '{\"path\":\"/root/docker/arcane/data/projects/slskd\"}'"

ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- curl -X POST http://localhost:3552/api/projects \
    -H 'Content-Type: application/json' \
    -d '{\"path\":\"/root/docker/arcane/data/projects/soularr\"}'"

# Or deploy via Arcane web UI:
# 1. Open http://192.168.1.142:3552
# 2. Add Project → /root/docker/arcane/data/projects/slskd/
# 3. Add Project → /root/docker/arcane/data/projects/soularr/
# 4. Start both projects
```

### Phase 6: Configure API Keys

```bash
# Update config.ini with the generated slskd API key
sed -i "s/SLSKD_API_KEY_GOES_HERE/$SLSKD_API_KEY/" /root/docker/soularr/config/config.ini

# Update config.ini with Lidarr API key (retrieved from Lidarr UI)
sed -i "s/LIDARR_API_KEY_GOES_HERE/<actual-lidarr-key>/" /root/docker/soularr/config/config.ini
```

### Phase 7: Router Port Forward

Not required. slskd works in outbound-only mode. Downloads will be slower for niche albums but fully functional for the vast majority of wanted music.

### Phase 8: Verify

```bash
# From workstation:
# 1. slskd web UI
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.142:5030
# Expected: 200 (login page)

# 2. soularr web UI  
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.142:8265
# Expected: 200

# 3. Check LXC logs
ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- docker logs slskd --tail 20"

ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- docker logs soularr --tail 20"

# 4. Test API access
ssh -i ~/.ssh/homelab_key root@192.168.1.134 \
  "pct exec 101 -- curl -s -H 'X-API-Key: $SLSKD_API_KEY' http://slskd:5030/api/v0/transfers"
```

---

## 7. Rollback Procedure

```bash
# 1. Stop and remove Arcane projects
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- \
  curl -X DELETE http://localhost:3552/api/projects/slskd && \
  curl -X DELETE http://localhost:3552/api/projects/soularr"

# 2. Remove config directories
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- \
  rm -rf /root/docker/slskd /root/docker/soularr /data/soulseek"

# 3. Remove Arcane project dirs
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- \
  rm -rf /root/docker/arcane/data/projects/slskd \
         /root/docker/arcane/data/projects/soularr"

# 4. Remove Docker network (if no other containers use it)
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- docker network rm soularrnet"

# 5. ~~Remove router port forward for 50300~~ (not applicable — out of scope)

# 6. Revert docker/README.md changes
```

---

## 8. Security Considerations

### API Key Management

| Secret | Storage | Location |
|--------|---------|----------|
| Lidarr API key | config.ini (plaintext) | `/root/docker/soularr/config/config.ini` — read-only by soularr container |
| slskd API key | `.env` + config.ini | `.env`: Arcane injects as env var; `config.ini`: soularr reads for auth |
| Soulseek credentials | slskd.yml (plaintext) | `/root/docker/slskd/config/slskd.yml` — local network only |

**Threat model:** All services run on a LAN behind NAT. No external access except:
- slskd P2P port (50300) — forwarded for Soulseek network
- Sonarr/Radarr/Lidarr/Jellyfin proxied via NPM with DuckDNS

**Recommendations:**
- Use a dedicated Soulseek account (not personal credentials) — consider an app-specific login
- slskd API key should be a random 64-char hex string (`openssl rand -hex 32`)
- Restrict slskd web UI to LAN (already limited by Docker host binding)
- soularr web UI is LAN-only (no NPM proxy per proposal scope)

### No VPN

Per proposal scope, Soulseek traffic does NOT use a VPN. Implications:

| Risk | Impact | Mitigation |
|------|--------|------------|
| IP visible to Soulseek peers | Low for music downloading | Peer-to-peer for music only; no DMCA enforcement typical for Soulseek |
| ISP throttling P2P | Low | Soulseek P2P port is configurable if needed |
| Legal risk | Low | Pulling music already in Lidarr wanted list; user owns media |

**Future option:** If VPN is desired, routeslskd+soularr through Gluetun container (pattern exists in project for Deluge).

### File Permissions

Both containers run as UID 1000 (matching the `arrsuite` user). Downloaded files:

```
/data/soulseek/downloads/  →  1000:1000
/data/soulseek/incomplete/ →  1000:1000
```

This ensures Lidarr (also UID 1000) can read and import files without permission errors.

---

## 9. Verification Matrix

| # | Criteria | Method | Expected |
|---|----------|--------|----------|
| 1 | slskd web UI reachable | `curl http://192.168.1.142:5030` | HTTP 200 (login page) |
| 2 | soularr web UI reachable | `curl http://192.168.1.142:8265` | HTTP 200 (dashboard) |
| 3 | slskd API authenticates | `curl -H 'X-API-Key: $KEY' http://slskd:5030/api/v0/transfers` | HTTP 200 (JSON) |
| 4 | soularr logs show no errors | `docker logs soularr --tail 30` | No tracebacks, connected to Lidarr |
| 5 | Lidarr wanted album searchable | Add album to Lidarr wanted list, check soularr logs after 5 min | "Searching for ..." |
| 6 | Download lands in `/data/soulseek/` | `ls -la /data/soulseek/downloads/` after search | Directory structure created |
| 7 | Lidarr imports completed download | Check Lidarr Activity Queue | Album appears in library |
| 8 | Clean restart | `docker restart slskd soularr` | Both return healthy (check docker ps) |
| 9 | Persistent across LXC reboot | `pct reboot 101` (Proxmox) | Both containers auto-start |

---

## 10. Repo Files to Create/Modify

| File | Action | Content |
|------|--------|---------|
| `docker/slskd/compose.yml` | **Create** | slskd compose definition |
| `docker/slskd/slskd.yml` | **Create** | slskd configuration reference |
| `docker/soularr/compose.yml` | **Create** | soularr compose definition |
| `docker/soularr/config.ini` | **Create** | soularr configuration reference |
| `docker/README.md` | **Modify** | Add services to stack table, storage layout, service URLs |

---

## 11. Open Questions / Risks

| Item | Question | Resolution |
|------|----------|------------|
| Soulseek account | User needs to register | Pre-deployment step |
| Lidarr API key | Key exists but needs retrieval | Get from Lidarr UI before deployment |
| slskd API key generation | Key must be generated and stored in two places | `openssl rand -hex 32` during deploy |
| `use_selected_lidarr_release = True` | User must manually select releases in Lidarr for soularr to act | Documented behavior — not a bug |
| Download filtering | First album may be non-music (README, etc.) | `download_filtering = True` mitigates |
| soularr image tag | `latest` may have breaking changes | Pin to version after initial validation |
