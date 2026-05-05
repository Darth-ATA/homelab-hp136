# Docker Services (LXC 101)

This directory contains docker-compose files for services running in the Docker LXC container (192.168.1.142).

## Services

| Service | Directory | Compose File | Container Name | Ports | Description |
|---------|-----------|--------------|----------------|-------|-------------|
| Nginx Proxy Manager | `npm/` | `compose.yaml` | `npm-app-1` | 80, 81, 443 | Reverse proxy + SSL termination |
| Arcane | `arcane/` | `compose.yml` | `arcane` | 3552 | Game server management |
| Vaultwarden | `vaultwarden/` | `compose.yml` | `vaultwarden` | 8080 | Bitwarden-compatible password manager |

## Deployment

To deploy a service:

```bash
# 1. Create compose file in this directory
# (e.g., docker/vaultwarden/compose.yml)

# 2. Copy to Proxmox host temp location
scp -i ~/.ssh/homelab_key docker/<service>/compose.yml root@192.168.1.134:/tmp/<service>-compose.yml

# 3. Create directory in LXC and push file
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- mkdir -p /root/docker/<service>"
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct push 101 /tmp/<service>-compose.yml /root/docker/<service>/compose.yml"

# 4. Start service
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- bash -c 'cd /root/docker/<service> && docker compose up -d'"
```

## Verify Running Services

```bash
# List all Docker containers in LXC 101
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- docker ps"
```

## Vaultwarden Specifics

- **Domain:** `vw.hp136.duckdns.org`
- **Internal Port:** 8080 (mapped to container port 80)
- **Data Location:** `/root/docker/vaultwarden/data` (persistent volume)
- **Proxy:** Managed by Nginx Proxy Manager
- **Signups:** Currently enabled - disable after creating account by editing `compose.yml` and running `docker compose down && docker compose up -d`

## Notes

- All compose files follow the pattern: `/root/docker/<service>/compose.yml`
- Services are managed independently (each has its own directory)
- NPM handles SSL termination for all services
- After creating your Vaultwarden account, set `SIGNUPS_ALLOWED=false` in the compose file
