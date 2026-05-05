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
├── firewall.tf                  # Firewall configuration (cluster, security groups, rules)
├── homeassistant-vm.tf          # Home Assistant VM firewall options
├── adguard-container.tf         # AdGuard LXC container
├── docker-container.tf          # Docker/NPM LXC container
├── tailscale-container.tf       # Tailscale LXC container
├── debian-test-container.tf     # Test LXC container
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
| 100 | homeassistant | Home Assistant VM (HAOS) - Firewall options managed by Terraform. Backups: see Storage Strategy | 192.168.1.100 |
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

## Firewall Configuration ✅

The firewall is **enabled with permissive ACCEPT policies** to avoid breaking existing services. See [Issue #3](https://github.com/Darth-ATA/homelab-hp136/issues/3) for implementation details.

### Status (2026-05-05)
- ✅ Cluster-level firewall enabled
- ✅ Security groups created (mgmt, dns, web, homeassistant, tailscale)
- ✅ Cluster firewall rules applied
- ✅ Container-level firewall enabled on all LXC containers
- ✅ Home Assistant VM firewall options configured

### Architecture

- **Cluster-level firewall**: Enabled with ACCEPT policies (input/output)
- **Security Groups**: Reusable rule sets for common services
- **Container-level firewall**: Enabled on all LXC containers (`firewall = true` on network interfaces)

### Security Groups Defined

| Group | Purpose | Target | Ports |
|-------|---------|--------|-------|
| `mgmt` | Management access (SSH + Proxmox UI) | 192.168.1.134 | 22, 8006 |
| `dns` | AdGuard DNS | 192.168.1.2 | 53/tcp+udp |
| `web` | Docker/NPM services | 192.168.1.142 | 80, 443, 81 |
| `homeassistant` | Home Assistant UI | 192.168.1.100 | 8123 |
| `tailscale` | Tailscale direct connections | 192.168.1.102 | 41641/udp |

### Services & Ports

| Service | IP | Open Ports | Notes |
|---------|-----|------------|-------|
| Proxmox Host | 192.168.1.134 | 8006 (UI), 22 (SSH) | Permissive (future: restrict to management IPs) |
| Home Assistant (VM 100) | 192.168.1.100 | 8123 | VM not managed; firewall options ARE managed ✅ |
| Docker/NPM (LXC 101) | 192.168.1.142 | 80, 443, 81 | NPM + Arcane |
| Tailscale (LXC 102) | 192.168.1.102 | 41641/UDP | Optional direct connections |
| AdGuard (LXC 103) | 192.168.1.2 | 53/tcp+udp | DNS server |
| Debian Test (LXC 105) | 192.168.1.105 | - | Test container |

### Firewall Files

- `firewall.tf` - Cluster firewall, security groups, and rules
- `homeassistant-vm.tf` - Home Assistant VM firewall options

### Future Hardening

A follow-up issue will restrict SSH and Proxmox UI to management IPs only, and potentially implement VLAN for IoT devices.

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

**Note:** Consider moving VM 100 backups from `local` to `local-zfs` for better compression. See [Storage Strategy](#storage-strategy).

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

## Storage Strategy

### Storage Allocation

| Storage | Type | Total | Used | Available | Used By |
|---------|------|-------|------|-----------|---------|
| `local` (dir) | Directory | 468GB | 105GB (22.5%) | 363GB | Proxmox ISOs, templates, VM 100 backups |
| `local-zfs` (zfs) | ZFS pool | 370GB | 7.4GB (2%) | 362GB | Container disks (101, 102, 103, 105), container backups |

### Why `local-zfs` for Containers
- **ZFS compression** reduces actual disk usage
- Better performance for container workloads
- All container disks and backups are already on `local-zfs` ✓

### VM 100 (Home Assistant) Backup Storage
Currently, HAOS backups are stored on `local` (dir). To optimize storage:

**Option A: Via Proxmox Web UI**
1. Go to Datacenter → Backup
2. Find the backup job for VM 100
3. Edit → Change Storage from `local` to `local-zfs`
4. Save and run a test backup

**Option B: Via CLI**
```bash
# Edit backup job (find job ID first)
ssh root@192.168.1.134 "cat /etc/pve/jobs.cfg"

# Or run one-time backup to local-zfs
ssh root@192.168.1.134 "vzdump 100 --storage local-zfs --mode snapshot"
```

**Cleanup old backups (keep last 3-5):**
```bash
# List HAOS backups
ssh root@192.168.1.134 "ls -lht /var/lib/vz/dump/vzdump-qemu-100-*.vma.*"

# Remove old backups (example - adjust dates as needed)
ssh root@192.168.1.134 "rm /var/lib/vz/dump/vzdump-qemu-100-2026_0*"
```

### Cleanup: Unused Templates/ISOs
```bash
# Check what's in templates directory
ssh root@192.168.1.134 "ls -lh /var/lib/vz/template/cache/ /var/lib/vz/template/iso/"

# Remove unused templates (verify first!)
ssh root@192.168.1.134 "rm /var/lib/vz/template/cache/<unused-template>.tar.gz"
```

### Disk Size Recommendations
| Container | Current Size | Recommendation |
|-----------|--------------|----------------|
| docker (101) | 32GB | Monitor - sufficient for Docker + NPM |
| tailscale (102) | 2GB | Sufficient for Tailscale only |
| adguard (103) | 2GB | Sufficient for DNS |
| debian-test (105) | 8GB | Adequate for testing |

### Restore Procedures

See [RECOVERY.md](./RECOVERY.md) for detailed restore instructions.
