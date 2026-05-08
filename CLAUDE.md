# CLAUDE.md - Project Context for AI Agents

## Quick Start - Connecting to Proxmox

**Proxmox Host:** 192.168.1.134
**SSH User:** root
**SSH Key:** ~/.ssh/homelab_key
**Web UI:** https://192.168.1.134:8006

### Basic SSH Connection
```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134
```

### Running Commands Remotely
```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 "pct list"
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 "qm list"
```

### Accessing Containers (LXC)
```bash
# Exec command inside container
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct exec 101 -- docker ps"

# Shell inside container
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "pct enter 101"
```

### Accessing VMs
```bash
# Shell inside VM
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "qm terminal 100"

# Exit qemu terminal: Ctrl-]
```

## Container/VM IDs

| ID | Name | Type | IP |
|----|------|------|-----|
| 100 | home_assistant | VM | 192.168.1.100 |
| 101 | docker | LXC | 192.168.1.142 |
| 102 | tailscale | LXC | 192.168.1.102 |
| 103 | adguard | LXC | 192.168.1.2 |
| 105 | debian-test | LXC | 192.168.1.105 |

## Terraform

- **API Endpoint:** https://192.168.1.134:8006/api2/json
- **API Token:** In terraform.tfvars (NOT committed to git)
- **Provider:** bpg/proxmox

Run terraform commands in the project root:
```bash
cd /Users/alejandrotorresaguilera/homelab-terraform
terraform plan
terraform apply
```

## Key Files

- `.claude/rules.md` - AI agent rules and best practices
- `README.md` - Full project documentation
- `NETWORK.md` - Network configuration details
- `docker/` - Docker compose files for media stack services
- `docs/download-pipeline-troubleshooting.md` - Sonarr/Prowlarr/Deluge fix guide

## Important Notes

1. **NEVER commit credentials** - terraform.tfvars and .env files are gitignored
2. **Check .claude/rules.md** for NPM documentation requirements
3. **Container disks are on local-zfs**, backups go to `local` (dir storage)