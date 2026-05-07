# NPM Recovery Skill

## Name

`npm-recovery` - Nginx Proxy Manager Recovery and Recreation

## Description

This skill provides a shell script for recovering and recreating Nginx Proxy Manager (NPM) proxy hosts in the homelab environment. It manages DuckDNS subdomain proxy configurations with SSL certificates.

## Prerequisites

Before using this skill, ensure you have:

- **SSH access** to the Proxmox host or direct access to the NPM container
- **Valid NPM credentials** (admin email and password)
- **SSL certificate** configured in NPM (wildcard certificate for *.duckdns.org)
- Required commands:
  - `ssh` - SSH client for remote access
  - `curl` - HTTP requests to NPM API
  - `jq` - JSON parsing

## Usage

### Basic Commands

```bash
# Recreate all proxy hosts (default)
./recovery.sh recreate

# Login to NPM API
./recovery.sh login

# List all proxy hosts
./recovery.sh list

# Create a specific proxy host
./recovery.sh create <subdomain>

# Delete a proxy host
./recovery.sh delete <domain>
```

### Detailed Examples

#### Login to NPM

```bash
NPM_API_USER="admin@example.com" NPM_API_PASS="yourpassword" ./recovery.sh login
```

#### List Existing Proxy Hosts

```bash
# First login to get token, then list
NPM_TOKEN="$(NPM_API_USER="admin@example.com" NPM_API_PASS="password" ./recovery.sh login)"
./recovery.sh list
```

#### Recreate All Proxy Hosts

```bash
# Recreate all proxy hosts with default settings
./recovery.sh recreate
```

#### Create Single Proxy Host

```bash
./recovery.sh create npm
```

#### Delete Proxy Host

```bash
./recovery.sh delete npm.hp136.duckdns.org
```

## Variables to Customize

### SSH Configuration

| Variable | Default | Description |
|---------|---------|-------------|
| `NPM_SSH_KEY_PATH` | `~/.ssh/homelab_key` | SSH private key path |
| `NPM_SSH_HOST` | `192.168.1.134` | Proxmox host IP (NOT container) |
| `NPM_SSH_PORT` | `22` | SSH port |
| `NPM_SSH_USER` | `root` | SSH username |
| `NPM_CONTAINER_ID` | `101` | Docker container ID on Proxmox |

### NPM API Configuration

| Variable | Default | Description |
|---------|---------|-------------|
| `NPM_API_URL` | `http://localhost:81` | NPM API URL |
| `NPM_API_USER` | `hasbringer1007@gmail.com` | NPM admin email |
| `NPM_API_PASS` | `Levantes1007` | NPM admin password |

### DuckDNS Configuration

| Variable | Default | Description |
|---------|---------|-------------|
| `DUCKDNS_DOMAIN` | `hp136` | DuckDNS subdomain |
| `SSL_CERT_ID` | `3` | SSL certificate ID |

### Logging

| Variable | Default | Description |
|---------|---------|-------------|
| `LOG_FILE` | `/var/log/npm-recovery.log` | Log file path |
| `DEBUG` | `0` | Enable debug output (1/0) |

## Naming Convention

The proxy hosts follow this naming pattern:

```
<subdomain>.<domain>.duckdns.org
```

For example: `npm.hp136.duckdns.org`

### Current Proxy Hosts

| Subdomain | Target | Description |
|----------|--------|-------------|
| `arcane` | 192.168.1.142:3552 | Arcane |
| `npm` | 192.168.1.142:81 | Nginx Proxy Manager |
| `vw` | 192.168.1.142:8080 | Volkswagen |
| `ha` | 192.168.1.100:8123 | Home Assistant (with websockets) |
| `agh` | 192.168.1.2:80 | AdGuard Home |
| `jelly` | 192.168.1.142:8096 | Jellyfin |
| `rad` | 192.168.1.142:7878 | Radarr |
| `son` | 192.168.1.142:8989 | Sonarr |
| `prowlarr` | 192.168.1.142:9696 | Prowlarr |
| `qbit` | 192.168.1.142:8081 | qBittorrent |

### SSL Certificate

- Certificate ID: `3`
- Domain: `*.hp136.duckdns.org`
- Provider: Let's Encrypt (via DuckDNS)

## Files

- `recovery.sh` - Main recovery script
- SKILL.md - This documentation

## Error Handling

The script includes:

- Strict mode (`set -Eeuo pipefail`)
- Input validation (domain, port)
- Dependency checking
- Comprehensive logging with timestamps
- Error trapping with line numbers

## Technical Details

### API Endpoints Used

- `POST /api/admin/login` - Authentication
- `GET /api/nginx/proxy-hosts` - List proxy hosts
- `POST /api/nginx/proxy-hosts` - Create proxy host
- `PUT /api/nginx/proxy-hosts/{id}` - Update proxy host
- `DELETE /api/nginx/proxy-hosts/{id}` - Delete proxy host

### Proxy Host Configuration

Each proxy host is configured with:

- SSL forced (HTTPS redirect)
- HTTP/2 support enabled
- Let's Encrypt certificate
- Forward scheme: HTTP