# Docker Services (LXC 101)

This directory contains reference copies of docker-compose files for services running in the Docker LXC container (192.168.1.142).

> **Vaultwarden was migrated to a dedicated LXC (ID 104, Alpine, 192.168.1.144).** See [NETWORK.md](../NETWORK.md) for details. The vaultwarden/ Arcane project is now inactive.

## Service Management

**All services are managed via [Arcane](https://getarcane.app)** — a project-based Docker orchestrator.

Arcane runs at `http://192.168.1.142:3552` and manages individual compose files per project under `/root/docker/arcane/data/projects/`.

**Do NOT use raw `docker compose` for individual services** — Arcane handles lifecycle, updates, and dependency ordering.

```bash
# To manage services, use Arcane web UI or the Arcane CLI:
# The underlying compose files are at:
/root/docker/arcane/data/projects/
# ├── sonarr/
# ├── radarr/
# ├── lidarr/
# ├── prowlarr/
# ├── deluge/
# ├── bazarr/
# ├── jellyfin/
# ├── npm/
# ├── vaultwarden/ (inactive — migrated to LXC 104)
# └── qbittorrent/ (inactive — Deluge is the active torrent client)
```

## Running Services

| Service | Container Name | Port | Description | Managed By |
|---------|---------------|------|-------------|-----------|
| Nginx Proxy Manager | `npm-app` | 80, 81, 443 | Reverse proxy + SSL termination | Arcane |
| Arcane | `arcane` | 3552 | Docker orchestrator | Arcane itself |
| **Deluge** | `deluge` | 8112, 6881 | **Active** torrent client (no VPN) | Arcane |
| Prowlarr | `prowlarr` | 9696 | Indexer management | Arcane |
| Radarr | `radarr` | 7878 | Movies automation | Arcane |
| Sonarr | `sonarr` | 8989 | TV shows automation | Arcane |
| Lidarr | `lidarr` | 8686 | Music collection manager | Arcane |
| **Bazarr** | `bazarr` | 6767 | Subtitle management | Arcane |
| Jellyfin | `jellyfin` | 8096, 8920 | Media server | Arcane |

## Configured but Not Deployed

These services have compose files on the host but are NOT running:

| Service | Dir | Port | Why not deployed |
|---------|-----|------|-----------------|
| qBittorrent | `qbittorrent/` | 8080 | Replaced by Deluge (no VPN needed) |
| Frigate | `frigate/` | 5000 | Needs RTSP camera auth + GPU validation |
| Immich | `immich/` | 2283 | Not yet set up |

## Storage Layout

**CRITICAL — Single Mount Rule:** All \*arr containers mount `/data:/data` as a single volume so **hardlinks work** inside Docker containers.

```
/data/                              # Single bind mount from Proxmox host
├── torrents/                       # Deluge downloads here
│   ├── movies/
│   ├── tv/
│   └── music/
└── media/                          # Organized media (*arr hardlinks here)
    ├── movies/
    ├── tv/
    └── music/
```

### Why Single Mount?
Docker creates a separate mount point for each bind mount. Even when source directories share the same ZFS subvol, Docker sees them as different filesystems and hardlinks fail with "Cross-device link" (EXDEV).

### \*Arr Root Folder Paths (with `/data:/data` mount)

| Service | Root Folder |
|---------|-------------|
| Radarr | `/data/media/movies` |
| Sonarr | `/data/media/tv` |
| Lidarr | `/data/media/music` |

## Deployment (Fresh LXC)

If you need to deploy the full stack on a new LXC 101:

```bash
# 1. Copy compose files to LXC
# (The docker/ directory in this repo has reference copies)

# 2. Set up Arcane
# See docs/deploy-arcane.md

# 3. Start Arcane (it manages the rest)
cd /root/docker/arcane && docker compose up -d

# 4. Access Arcane UI at http://192.168.1.142:3552
#    Add each project from /root/docker/arcane/data/projects/
```

**Automated option:** Run `./scripts/deploy-arcane.sh` then use the Arcane UI to add projects.

## Service URLs

- **Deluge**: http://192.168.1.142:8112
- **Prowlarr**: http://192.168.1.142:9696
- **Radarr**: http://192.168.1.142:7878
- **Sonarr**: http://192.168.1.142:8989
- **Lidarr**: http://192.168.1.142:8686
- **Bazarr**: http://192.168.1.142:6767
- **Jellyfin**: http://192.168.1.142:8096
- **Vaultwarden**: https://vw.hp136.duckdns.org (LXC 104, proxied via NPM)
- **NPM Admin**: http://192.168.1.142:81
- **Arcane**: http://192.168.1.142:3552

## Nginx Proxy Manager Configuration

Add proxy hosts in NPM (http://192.168.1.142:81):
- `prowlarr.hp136.duckdns.org` → 192.168.1.142:9696
- `radarr.hp136.duckdns.org` → 192.168.1.142:7878
- `sonarr.hp136.duckdns.org` → 192.168.1.142:8989
- `lidarr.hp136.duckdns.org` → 192.168.1.142:8686
- `jellyfin.hp136.duckdns.org` → 192.168.1.142:8096

## Verify Running Services

```bash
# List all Docker containers in LXC 101
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- docker ps --format 'table {{.Names}}\t{{.Ports}}'"
```

## Notes

- All services are on the `arrsuite` Docker network (or default bridge)
- Media storage uses `/data` single mount point from Proxmox host
- **Deluge** (not qBittorrent) is the active torrent client — no VPN
- After creating accounts in any service, disable signups
- The `docker/` directory in this repo has **reference copies** — the live files live on the LXC under `/root/docker/`
