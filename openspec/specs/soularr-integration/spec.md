# Soularr Integration Specification

Bridge Lidarr to Soulseek P2P via slskd so music unavailable on public torrent trackers becomes acquirable. Two containers (slskd + soularr) on LXC 101 under Arcane share a download directory with Lidarr for auto-import.

## Requirements

### REQ-001: slskd daemon

slskd MUST run as an Arcane container on LXC 101 with web UI on :5030 and P2P on :50300. It MUST use PUID/PGID 1000, TZ Europe/Madrid, `/data` mount. Config at `/root/docker/slskd/`. It MUST generate an API key at startup for soularr auth.

**Scenario: Container starts**
- GIVEN the slskd image is pulled
- WHEN Arcane starts the container
- THEN web UI is reachable at http://192.168.1.142:5030
- AND logs show API key generation

**Scenario: P2P port blocked**
- GIVEN port 50300 is unreachable from WAN
- WHEN slskd starts
- THEN slskd logs a connection warning
- AND soularr searches still work (fewer peers)

### REQ-002: soularr automation

soularr MUST run as an Arcane container on LXC 101 with web UI on :8265. It MUST use PUID/PGID 1000, TZ Europe/Madrid, `/data` mount. Config at `/root/docker/soularr/`. It MUST poll Lidarr wanted list every 5 min, use `use_selected_lidarr_release = True`, and reference both API keys from `config.ini`.

**Scenario: Wanted album downloaded**
- GIVEN Lidarr has a wanted album with no active download
- WHEN soularr polls Lidarr API
- THEN soularr searches slskd via slskd
- AND best-quality match downloads to `/data/soulseek/`

**Scenario: No Soulseek results**
- GIVEN a wanted album has no Soulseek matches
- WHEN soularr searches slskd
- THEN soularr logs zero results
- AND retries next cycle

**Scenario: Lidarr API down**
- GIVEN Lidarr API is unreachable
- WHEN soularr attempts to poll
- THEN soularr logs an API error
- AND retries next cycle

**Scenario: slskd API down**
- GIVEN slskd API is not responding
- WHEN soularr attempts to search
- THEN soularr logs a slskd error
- AND retries next cycle

### REQ-003: Shared download storage

Both containers MUST write to `/data/soulseek/`. Lidarr MUST import from `/data/soulseek/` to `/data/media/music/`. Hardlinks MUST work (same `/data` mount).

**Scenario: Successful import**
- GIVEN a download completes in `/data/soulseek/`
- WHEN Lidarr processes its download queue
- THEN the file imports to `/data/media/music/`
- AND `/data/soulseek/` retains a hardlink

**Scenario: Permission denied**
- GIVEN `/data/soulseek/` ownership is not PUID 1000
- WHEN soularr tries to write a download
- THEN the download fails
- AND soularr logs a permission error
### REQ-004: P2P network ingress (deferred)

Router port forwarding is NOT configured. slskd operates in outbound-only mode
— it connects to peers but doesn't accept incoming connections. This reduces
available peers but is fully functional for downloading music.

**Scenario: Outbound-only connectivity**
- GIVEN no port forward for :50300
- WHEN slskd starts
- THEN slskd logs a warning about no incoming connections
- BUT soularr searches still work and downloads proceed

### REQ-005: Service recovery

Both containers MUST restart on LXC 101 reboot (Arcane restart policy).

**Scenario: Cold start after reboot**
- GIVEN LXC 101 reboots
- WHEN Arcane starts both containers
- THEN slskd is reachable at :5030 within 60s
- AND soularr is reachable at :8265 within 60s
- AND soularr resumes polling on the next cycle

## Acceptance Criteria

- [ ] slskd UI at http://192.168.1.142:5030
- [ ] soularr UI at http://192.168.1.142:8265
- [ ] Lidarr wanted album in soularr queue
- [ ] Download completes in `/data/soulseek/`, Lidarr imports to `/data/media/music/`
- [ ] Both containers restart on LXC 101 reboot
