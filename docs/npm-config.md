# Nginx Proxy Manager (NPM) Configuration

## Access Information

| Property | Value |
|----------|-------|
| **URL** | http://192.168.1.142:81 |
| **Email** | hasbringer1007@gmail.com |
| **Password** | *(stored in scripts)* |
| **SSL Certificate** | *.hp136.duckdns.org (Let's Encrypt via DuckDNS) |

## Current Proxy Hosts

All services are accessible via `https://<service>.hp136.duckdns.org`

| Subdomain | Full Domain | Target | Port | Notes |
|-----------|-------------|--------|------|-------|
| arcane | arcane.hp136.duckdns.org | 192.168.1.142 | 3552 | Arcane |
| npm | npm.hp136.duckdns.org | 192.168.1.142 | 81 | Nginx Proxy Manager |
| vw | vw.hp136.duckdns.org | 192.168.1.142 | 8080 | Volkswagen |
| ha | ha.hp136.duckdns.org | 192.168.1.100 | 8123 | Home Assistant (websockets enabled) |
| agh | agh.hp136.duckdns.org | 192.168.1.2 | 80 | AdGuard Home |
| jelly | jelly.hp136.duckdns.org | 192.168.1.142 | 8096 | Jellyfin |
| rad | rad.hp136.duckdns.org | 192.168.1.142 | 7878 | Radarr |
| son | son.hp136.duckdns.org | 192.168.1.142 | 8989 | Sonarr |
| prowlarr | prowlarr.hp136.duckdns.org | 192.168.1.142 | 9696 | Prowlarr |
| qbit | qbit.hp136.duckdns.org | 192.168.1.142 | 8081 | qBittorrent |

## SSL Certificate

| Property | Value |
|----------|-------|
| **Domain** | *.hp136.duckdns.org |
| **Provider** | Let's Encrypt (via DuckDNS) |
| **Certificate ID** | 3 |

## Recovery Scripts

### Using recovery.sh

The `recovery.sh` script automates recreation of all proxy hosts. It requires SSH access to Proxmox and NPM API credentials.

**Location:** `docker/npm/recovery.sh`

```bash
# Navigate to the NPM directory
cd docker/npm

# Recreate all proxy hosts (default)
./recovery.sh recreate

# Login to NPM API
./recovery.sh login

# List configured proxy hosts
./recovery.sh list

# Create a specific proxy host
./recovery.sh create <subdomain>

# Delete a proxy host
./recovery.sh delete <domain>
```

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `NPM_SSH_KEY_PATH` | ~/.ssh/homelab_key | SSH private key |
| `NPM_SSH_HOST` | 192.168.1.134 | Proxmox host IP |
| `NPM_CONTAINER_ID` | 101 | NPM container ID |
| `NPM_API_URL` | http://localhost:81 | NPM API URL |
| `NPM_API_USER` | hasbringer1007@gmail.com | NPM admin email |
| `NPM_API_PASS` | Levantes1007 | NPM admin password |
| `DUCKDNS_DOMAIN` | hp136 | DuckDNS subdomain |
| `SSL_CERT_ID` | 3 | SSL certificate ID |

### Using run_api.sh

The `run_api.sh` script authenticates with the NPM API and fetches certificate information.

**Location:** `docker/npm/run_api.sh`

```bash
cd docker/npm

# Create .env file with your credentials (see .env.example)
# Then run:
./run_api.sh
```

**Note:** This script requires a `.env` file with `NPM_API_USER` and `NPM_API_PASS` variables.

## Adding New Proxy Hosts

1. **Via NPM UI:**
   - Log in at http://192.168.1.142:81
   - Go to **Proxy Hosts** → **Add Proxy Host**
   - Fill in domain, scheme (http), forward hostname/IP, and port
   - Enable **SSL** and select the wildcard certificate
   - Enable **Websockets Support** if needed (e.g., Home Assistant)

2. **Via recovery.sh:**
   - Add new entry to `PROXY_HOSTS` variable in the script
   - Run `./recovery.sh create <subdomain>`

## Troubleshooting

- **SSL Certificate Issues:** Ensure DuckDNS wildcard certificate is issued (*.hp136.duckdns.org)
- **Connection Refused:** Check the target service is running
- **Websockets Not Working:** Enable "Websockets Support" in proxy host settings

## Related Documentation

- **NPM Recovery Skill:** See `.claude/skills/npm-recovery/SKILL.md` for detailed API and script documentation
- **Proxmox Access:** See `.claude/rules.md` for SSH access details