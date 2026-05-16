---
name: homelab-proxmox
description: Manage Proxmox homelab infrastructure with Terraform. Use when working with this homelab's LXC containers, VMs, firewall, backups, or Docker stack.
---

# Homelab Proxmox Infrastructure

This skill provides context-specific guidance for the homelab-hp136 project.

## Project Overview

**Target**: Intel N100 (16GB RAM, 512GB SSD) running Proxmox VE
**Host**: 192.168.1.134 (prxhp136)
**Goal**: Full IaC to regenerate entire homelab on new hardware

## Infrastructure

| ID  | Name        | Type          | IP            | Specs                  |
| --- | ----------- | ------------- | ------------- | ---------------------- |
| 100 | home_assistant | VM (HAOS)  | 192.168.1.100 | 4GB RAM, 32GB disk     |
| 101 | docker      | LXC           | 192.168.1.142 | 2 cores, 4GB RAM, 32GB |
| 102 | tailscale   | LXC           | 192.168.1.102 | 1 core, 512MB, 2GB     |
| 103 | adguard     | LXC           | 192.168.1.2   | 1 core, 512MB, 2GB     |

## Docker Stack (LXC 101)

9 services via docker-compose:
- **Media**: Sonarr, Radarr, Lidarr, Prowlarr, Jellyfin, Deluge
- **Proxy**: nginx-proxy-manager (ports 80, 443, 81)
- **Other**: Arcane (tracker), Vaultwarden (password manager)

## Terraform Management

All containers and VMs ARE managed by Terraform. The `bpg/proxmox` provider (v0.76.0+) handles them correctly.

Terraform manages:
- Firewall configuration (security groups, rules)
- All LXC containers (create, modify, update)
- VM configuration (Home Assistant)
- Backup jobs

To import a new container after hardware change:
```bash
terraform import proxmox_virtual_environment_container.name prxhp136/ID
terraform plan  # Verify before apply
terraform apply
```

**Best Practice**: Run `terraform plan` before `apply` to detect any unintended replacements.

## Storage

| Storage    | Type  | Used  | Purpose              |
|------------|-------|-------|----------------------|
| local      | dir   | 22.5% | Backups, ISOs        |
| local-zfs  | zfs   | 2%    | Container disks      |

**Important**: Backups MUST use `local` (dir-type). ZFS pools do NOT support backup content type.

## Backup Strategy

- **Schedule**: Daily at 21:00-23:00
- **Retention**: Keep all current month, last of each previous month
- **Cleanup**: `/usr/local/bin/cleanup-backups.sh` via cron

## Networking

- Static IPs configured in Proxmox (not DHCP)
- AdGuard at 192.168.1.2 (primary DNS)
- All services documented in NETWORK.md

## Key Files

- `main.tf` - Provider configuration
- `firewall.tf` - Firewall rules
- `docker-container.tf` - Docker LXC config
- `adguard-container.tf` - AdGuard config
- `tailscale-container.tf` - Tailscale config
- `home_vm.tf` - Home Assistant VM
- `docker/` - Docker Compose files
- `docs/` - Troubleshooting guides
- `NETWORK.md` - IP allocation

## Commands

```bash
# SSH to Proxmox
ssh -i ~/.ssh/homelab_key root@192.168.1.134

# List containers
pct list

# List VMs
qm list

# Docker inside LXC
pct exec 101 -- docker ps

# Run Terraform
cd /Users/alejandrotorresaguilera/homelab-terraform
terraform plan
terraform apply
```

## Language

- **User communication**: Spanish (voseo)
- **Code and documentation**: English