# homelab-hp136

Terraform configuration for managing LXC containers on Proxmox VE using the `bpg/proxmox` provider.

## Overview

This project provides Infrastructure as Code (IaC) for a Proxmox homelab environment. It allows you to create, modify, and manage LXC containers programmatically instead of using the Proxmox web interface interactively.

**Note:** This setup uses Terraform mainly for **creating new containers**. Due to known bugs in the `bpg/proxmox` provider with imports (issues #1406, #1998), existing containers are documented but not managed by Terraform to avoid unintended replacements.

## Project Structure

```
homelab-terraform/
├── main.tf                      # Provider and base configuration
├── variables.tf                 # Variable definitions
├── new-container-example.tf     # Template for new containers
├── NETWORK.md                   # Network configuration and static IPs
├── README.md                    # This file
├── .gitignore                  # Protect sensitive data
├── docs/                       # Additional documentation
│   ├── adguard-dns-records.md
│   ├── homeassistant-static-ip.md
│   └── npm-config.md
└── scripts/                    # Utility scripts
    └── set-static-ips.sh
```

## Prerequisites

- Terraform >= 1.0
- Proxmox VE with API enabled
- SSH access configured with keys (for manual imports if needed)
- Existing LXC templates on Proxmox (e.g., Debian 13)

## Setup

### 1. Create `terraform.tfvars` (not committed to Git):

```bash
cat > terraform.tfvars << 'EOL'
proxmox_api_token = "root@pam!terraform-token-root=YOUR_TOKEN_HERE"
proxmox_endpoint = "https://192.168.1.134:8006/api2/json"
EOL
```

### 2. Initialize Terraform:

```bash
terraform init
```

### 3. Create a new container:

- Copy `new-container-example.tf` to a new file or edit it
- Update `vm_id` (use an unused ID), `hostname`, and configuration
- Run:
  ```bash
  terraform plan
  terraform apply
  ```

## Existing Containers (Not managed by Terraform)

The following containers were created manually and are **NOT** under Terraform management to prevent unintended replacements due to provider bugs:

| ID  | Name      | Description | Static IP |
|-----|-----------|-------------|-----------|
| 100 | homeassistant | Home Assistant VM (HAOS) | 192.168.1.100 |
| 101 | docker    | Container with Docker + NPM + Arcane (2 cores, 4GB RAM) | 192.168.1.142 |
| 102 | tailscale  | Container with Tailscale (1 core, 512MB RAM) | 192.168.1.102 |
| 103 | adguard   | Container with AdGuard (1 core, 512MB RAM) | 192.168.1.2 |
| 105 | debian-test | Test container (1 core, 512MB RAM) | 192.168.1.105 |

**All services use static IPs configured in Proxmox/LXC/VM configs. See [NETWORK.md](./NETWORK.md) for complete network documentation.**

## Importing Containers (Advanced)

If you want to import an existing container (requires downtime):

```bash
# Import
terraform import proxmox_virtual_environment_container.name prxhp136/ID

# Verify
terraform show
```

**Warning:** The `bpg/proxmox` provider has known issues (#1406, #1998) that may cause forced replacements after import. Use with caution.

## Resources

- [bpg/proxmox Provider Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/index.html)

## Security

- API tokens and state files are excluded from Git via `.gitignore`
- Never commit `terraform.tfvars` or `.terraform/` directory
- Use sensitive variables for passwords and tokens

## Backup Strategy

### Backup Jobs Configured

| Resource | VMID | Schedule | Storage | Retention Policy |
|-----------|------|----------|---------|------------------|
| Home Assistant | 100 | Daily 21:00 | local (dir) | Last 3-5 backups |
| docker | 101 | Daily 22:00 | local-zfs (ZFS) | **Daily + Last of each month** |
| tailscale | 102 | Daily 22:30 | local-zfs (ZFS) | **Daily + Last of each month** |
| adguard | 103 | Daily 23:00 | local-zfs (ZFS) | **Daily + Last of each month** |

### Special Retention Policy

The cleanup script (`/usr/local/bin/cleanup-backups.sh`) implements a **custom retention policy**:

- **Current month:** Keep ALL daily backups
- **Previous months:** Keep ONLY the LAST backup (highest date) of each month
- **Purpose:** Maintain daily granularity for recent backups, but save space for older ones

### Cleanup Script

- **Location:** `/usr/local/bin/cleanup-backups.sh`
- **Scheduled:** Daily at 1:00 AM via cron
- **Log file:** `/var/log/backup-cleanup.log`
- **What it does:**
  1. Finds all `vzdump-*.vma.*` files in `/var/lib/vz/dump` and `/var/lib/vz/snapshot`
  2. Groups by year-month (from filename)
  3. Current month: Keep all
  4. Previous months: Delete all except the last backup (highest date)

### Manual Execution

```bash
# Run cleanup manually
ssh root@192.168.1.134 "/usr/local/bin/cleanup-backups.sh"

# Check log
ssh root@192.168.1.134 "cat /var/log/backup-cleanup.log"
```

### Restore Procedures

See [RECOVERY.md](./RECOVERY.md) for detailed restore instructions.
