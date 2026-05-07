# Arcane Deployment Guide

This document describes how to deploy the Arcane application using the script-based approach.

## Overview

Arcane is deployed using a **bash script** rather than Terraform. The deployment process works as follows:

1. The script connects to the Proxmox host via SSH
2. Uses `pct exec` to run commands inside the Docker LXC container
3. Copies `compose.yml` and `.env` files to the LXC
4. Runs `docker-compose up -d` to start the Arcane container

This approach provides:
- Faster deployment times (no Terraform plan/apply)
- Simpler rollback (just re-run the script)
- Direct control over the container lifecycle

## Prerequisites

Before deploying Arcane, ensure you have:

### 1. SSH Key Configuration

An SSH key must be configured for authentication to the Proxmox host.

- **Key location**: `~/.ssh/homelab_ata`
- **Target host**: `192.168.1.134`
- **SSH user**: `root`

Test your connection:

```bash
ssh -i ~/.ssh/homelab_ata -o StrictHostKeyChecking=no root@192.168.1.134
```

### 2. Proxmox LXC Running

The target LXC container (ID: **101**) must be running before deployment.

Check LXC status:

```bash
ssh -i ~/.ssh/homelab_ata -o StrictHostKeyChecking=no root@192.168.1.134 "pct status 101"
```

### 3. Source Files

Ensure the following files exist in `docker/arcane/`:

- `compose.yml` - Docker Compose configuration
- `.env` - Environment variables (copy from `.env.example`)

## Usage

### Deploy Arcane

Run the deployment script:

```bash
./scripts/deploy-arcane.sh
```

Expected output:

```
==============================================
  Arcane Deployment Script
  Target: LXC 101 @ 192.168.1.134
==============================================

[INFO] Validating prerequisites...
[SUCCESS] Prerequisites validated
[INFO] Checking LXC status...
[INFO] LXC status: running
[SUCCESS] LXC is running
[INFO] [1/5] Creating directory in LXC...
[SUCCESS] Directory created at /root/docker/arcane
[INFO] [2/5] Copying files to Proxmox temp...
[SUCCESS] Files copied to /tmp/
[INFO] [3/5] Pushing files to LXC...
[SUCCESS] Files pushed to /root/docker/arcane
[INFO] [4/5] Ensuring docker-compose is installed...
[SUCCESS] docker-compose ready
[INFO] [5/5] Deploying Arcane container...
[SUCCESS] Arcane container is running

==============================================
  Deployment Complete!
==============================================

[SUCCESS] Access Arcane at: http://192.168.1.142:3552
```

### Redeploy (Force)

To force a redeploy (removes existing container first):

```bash
./scripts/deploy-arcane.sh --redeploy
```

This is useful when:
- Container is in a broken state
- You want a clean deployment
- You've made changes to `compose.yml` and need to recreate

### Help

Display usage information:

```bash
./scripts/deploy-arcane.sh --help
```

Output:

```
Usage: ./deploy-arcane.sh [OPTIONS]

Options:
  --redeploy    Force redeploy (removes existing container first)
  -h, --help    Show this help message
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        LOCAL MACHINE                            │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │ deploy-arcane│───▶│  compose.yml │    │      .env        │   │
│  │    .sh       │    │              │    │ (ENCRYPTION_KEY │   │
│  └──────────────┘    └──────────────┘    │  JWT_SECRET)     │   │
│         │                                    └──────────────────┘         │
└─────────│────────────────────────────────────────────────────────┘         │
          │ SSH (key: ~/.ssh/homelab_ata)                                    │
          ▼                                                                   │
┌─────────────────────────────────────────────────────────────────┐
│                    PROXMOX HOST (192.168.1.134)                         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐             │
│  │                   LXC CONTAINER (ID: 101)                  │             │
│  │                                                          │             │
│  │  ┌────────────────┐    ┌────────────────────────────┐    │             │
│  │  │   Docker       │───▶│   Arcane Container         │    │             │
│  │  │   Daemon       │    │   (port 3552)              │    │             │
│  │  └────────────────┘    └────────────────────────────┘    │             │
│  │         │                                                      │             │
│  │  /root/docker/arcane/                                        │             │
│  │  - compose.yml                                              │             │
│  │  - .env                                                      │             │
│  └──────────────────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                                                    │
                                                    ▼
                                          ┌─────────────────┐
                                          │ Arcane Web UI   │
                                          │ http://192.168.1│
                                          │ .142:3552       │
                                          └─────────────────┘
```

### Deployment Flow

1. **Local → Proxmox**: Script copies `compose.yml` and `.env` to Proxmox temp (`/tmp/`)
2. **Proxmox → LXC**: Script uses `pct push` to transfer files into LXC at `/root/docker/arcane/`
3. **Inside LXC**: Script runs `docker-compose up -d` to start the container
4. **Verification**: Script checks container status and reports access URL

## Troubleshooting

### SSH Key Not Found

**Error**: `SSH key not found: ~/.ssh/homelab_ata`

**Solution**: Ensure the SSH key exists and the path is correct:

```bash
ls -la ~/.ssh/homelab_ata
```

If the key is in a different location, edit `SSH_KEY` in `deploy-arcane.sh`:

```bash
SSH_KEY="/path/to/your/key"
```

### LXC Not Running

**Error**: `LXC 101 is not accessible or not running`

**Solution**: Start the LXC:

```bash
ssh -i ~/.ssh/homelab_ata root@192.168.1.134 "pct start 101"
```

Then verify:

```bash
ssh -i ~/.ssh/homelab_ata root@192.168.1.134 "pct status 101"
```

### Container Not Starting

**Error**: `Container deployment may have failed`

**Solution**: Check container logs inside the LXC:

```bash
ssh -i ~/.ssh/homelab_ata root@192.168.1.134 "pct exec 101 -- docker logs arcane"
```

Also check container status:

```bash
ssh -i ~/.ssh/homelab_ata root@192.168.1.134 "pct exec 101 -- docker ps -a"
```

### Files Not Found

**Error**: `compose.yml not found` or `.env file not found`

**Solution**: Ensure you're running the script from the repository root:

```bash
cd /Users/alejandrotorresaguilera/homelab-terraform
./scripts/deploy-arcane.sh
```

Verify files exist:

```bash
ls -la docker/arcane/
```

### Port Already in Use

**Error**: Port 3552 is already bound

**Solution**: Check what's using the port:

```bash
ssh -i ~/.ssh/homelab_ata root@192.168.1.134 "pct exec 101 -- netstat -tlnp | grep 3552"
```

Either stop the conflicting service or change the port in `compose.yml`.

## Security Notes

### Sensitive Data in .env

The `.env` file contains sensitive configuration:

```bash
# secrets - DO NOT commit to Git!
ENCRYPTION_KEY=your-encryption-key-here
JWT_SECRET=your-jwt-secret-here
```

**Important**:
- **Never commit** `.env` to version control
- The `.gitignore` excludes this file
- Only `.env.example` should be committed (with placeholder values)
- Update these secrets in production deployment

### SSH Key Security

- The SSH key (`~/.ssh/homelab_ata`) should have restricted permissions:
  ```bash
  chmod 600 ~/.ssh/homelab_ata
  ```
- Never share or commit this key to version control

### Network Access

Arcane is accessible at `http://192.168.1.142:3552`. Consider:
- Configuring firewall rules to restrict access
- Using a reverse proxy with HTTPS for production
- Implementing authentication at the application level

## Configuration Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `LXC_ID` | Proxmox LXC container ID | `101` |
| `PROXMOX_HOST` | Proxmox host IP | `192.168.1.134` |
| `SSH_KEY` | Path to SSH private key | `~/.ssh/homelab_ata` |
| `APP_PORT` | Application port | `3552` |
| `APP_URL` | Full access URL | `http://192.168.1.142:3552` |

To modify these, edit the configuration section at the top of `deploy-arcane.sh`:

```bash
# Configuration
LXC_ID="101"
PROXMOX_HOST="192.168.1.134"
SSH_KEY="~/.ssh/homelab_ata"
LOCAL_DIR="$(cd "$(dirname "$0")/../docker/arcane" && pwd)"
REMOTE_DIR="/root/docker/arcane"
APP_PORT="3552"
APP_URL="http://192.168.1.142:${APP_PORT}"
```

## Quick Reference

```bash
# Deploy Arcane
./scripts/deploy-arcane.sh

# Force redeploy
./scripts/deploy-arcane.sh --redeploy

# View help
./scripts/deploy-arcane.sh --help

# Check container status (inside LXC)
ssh -i ~/.ssh/homelab_ata root@192.168.1.134 "pct exec 101 -- docker ps"

# View logs
ssh -i ~/.ssh/homelab_ata root@192.168.1.134 "pct exec 101 -- docker logs arcane"

# Restart container
ssh -i ~/.ssh/homelab_ata root@192.168.1.134 "pct exec 101 -- docker restart arcane"
```