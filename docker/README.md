# Docker Services (LXC 101)

This directory contains docker-compose files for services running in the Docker LXC container (192.168.1.142).

## Services

| Service | Directory | Compose File | Container Name | Ports | Description |
|---------|-----------|--------------|----------------|-------|-------------|
| Nginx Proxy Manager | `npm/` | `compose.yml` | `npm-app` | 80, 81, 443 | Reverse proxy + SSL termination |
| Arcane | `arcane/` | `compose.yml` | `arcane` | 3552 | Game server management |
| Vaultwarden | `vaultwarden/` | `compose.yml` | `vaultwarden` | 8080 | Bitwarden-compatible password manager |
| **qBittorrent** | `qbittorrent/` | `compose.yml` | `qbittorrent` | 8080* | Torrent client (behind VPN) |
| **Gluetun VPN** | `qbittorrent/` | `compose.yml` | `gluetun` | - | VPN tunnel (ProtonVPN) |
| **Prowlarr** | `prowlarr/` | `compose.yml` | `prowlarr` | 9696 | Indexer management |
| **Radarr** | `radarr/` | `compose.yml` | `radarr` | 7878 | Movies automation |
| **Sonarr** | `sonarr/` | `compose.yml` | `sonarr` | 8989 | TV shows automation |
| **Jellyfin** | `jellyfin/` | `compose.yml` | `jellyfin` | 8096 | Media server |

*Ports marked with * are routed through VPN tunnel

## Master Compose File

A complete `docker-compose.yml` at the root level includes all media services with proper networking. To use it:

```bash
cd /root/docker
cp .env.example .env
# Edit .env with your ProtonVPN credentials
nano .env
# Start all services
docker compose -f docker-compose.yml up -d
```

## Prerequisites

### 1. Storage Setup (on Proxmox host)
```bash
# SSH into Proxmox host
ssh root@192.168.1.134

# Create media folder structure
mkdir -p /mnt/media/{torrents,media}/{movies,tv,music}
chmod 777 -R /mnt/media

# Add bind mount to LXC 101
echo "mp0: /mnt/media,mp=/data" >> /etc/pve/lxc/101.conf
pct restart 101
```

### 2. VPN Credentials (ProtonVPN Free)
1. Sign up: https://protonvpn.com/free-vpn
2. Get OpenVPN credentials: https://account.protonvpn.com
   - Go to Downloads > OpenVPN configuration files
   - Click "Generate" next to "OpenVPN / IKEv2 username and password"
3. Edit `/root/docker/.env` with your credentials

## TRaSH Guides Configuration

After deploying, follow these guides:
- **qBittorrent**: https://trash-guides.info/Downloaders/qBittorrent/
- **Prowlarr**: https://trash-guides.info/Prowlarr/
- **Radarr**: https://trash-guides.info/Radarr/ (import quality profiles!)
- **Sonarr**: https://trash-guides.info/Sonarr/
- **Jellyfin**: Use Plex settings as reference: https://trash-guides.info/Plex/

### Quick Radarr/Sonarr Setup (TRaSH):
1. Access Radarr: http://192.168.1.142:7878
2. Settings > Indexers > Add Prowlarr (http://prowlarr:9696)
3. Settings > Download Clients > Add qBittorrent (http://gluetun:8080)
4. Import TRaSH Custom Formats: https://trash-guides.info/Radarr/Radarr-import-custom-formats/
5. Set root path: `/data/media/movies`
6. Repeat for Sonarr (TV: `/data/media/tv`)

## Deployment

### Option 1: Master Compose (Recommended)
```bash
# Copy to Proxmox host temp
scp -i ~/.ssh/homelab_key docker/docker-compose.yml root@192.168.1.134:/tmp/media-compose.yml
scp -i ~/.ssh/homelab_key docker/.env.example root@192.168.1.134:/tmp/media.env

# Push to LXC
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- mkdir -p /root/docker"
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct push 101 /tmp/media-compose.yml /root/docker/docker-compose.yml"
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct push 101 /tmp/media.env /root/docker/.env"

# Start services
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- bash -c 'cd /root/docker && docker compose up -d'"
```

### Option 2: Individual Services
```bash
# For each service (replace SERVICE with prowlarr/radarr/sonarr/jellyfin):
scp -i ~/.ssh/homelab_key docker/SERVICE/compose.yml root@192.168.1.134:/tmp/SERVICE-compose.yml
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- mkdir -p /root/docker/SERVICE"
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct push 101 /tmp/SERVICE-compose.yml /root/docker/SERVICE/compose.yml"
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- bash -c 'cd /root/docker/SERVICE && docker compose up -d'"
```

## Automated Deployment
```bash
# Run the deployment script (requires SSH access set up)
./scripts/deploy-media-stack.sh
```

## Verify Running Services
```bash
# List all Docker containers in LXC 101
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- docker ps"
```

## Service URLs
- **qBittorrent**: http://192.168.1.142:8080
- **Prowlarr**: http://192.168.1.142:9696
- **Radarr**: http://192.168.1.142:7878
- **Sonarr**: http://192.168.1.142:8989
- **Jellyfin**: http://192.168.1.142:8096

## Nginx Proxy Manager Configuration
Add proxy hosts in NPM (http://192.168.1.142:81):
- `qbittorrent.hp136.duckdns.org` → 192.168.1.142:8080
- `prowlarr.hp136.duckdns.org` → 192.168.1.142:9696
- `radarr.hp136.duckdns.org` → 192.168.1.142:7878
- `sonarr.hp136.duckdns.org` → 192.168.1.142:8989
- `jellyfin.hp136.duckdns.org` → 192.168.1.142:8096

## Notes
- All compose files follow the pattern: `/root/docker/<service>/compose.yml`
- Media storage uses `/data` mount (bound from Proxmox host `/mnt/media`)
- qBittorrent runs behind VPN (Gluetun) for privacy
- Arr apps connect to qBittorrent via internal Docker network
- Jellyfin has read-only access to media (`/data/media:/media:ro`)
- After creating accounts, disable signups in public-facing services
