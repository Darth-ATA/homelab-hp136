# homelab-hp136

Terraform configuration for managing LXC containers on Proxmox VE using the `bpg/proxmox` provider.

## Overview

This project provides Infrastructure as Code (IaC) for a Proxmox homelab environment. It allows you to create, modify, and manage LXC containers programmatically instead of using the Proxmox web interface interactively.

**Note:** This setup uses Terraform to **create, modify, and manage** all containers and VMs. All resources are managed safely via the `bpg/proxmox` provider (v0.76.0+).

## Project Structure

```
homelab-terraform/
├── main.tf                      # Provider and base configuration
├── variables.tf                 # Variable definitions
├── firewall.tf                  # Firewall configuration (cluster, security groups, rules)
├── home_vm.tf                   # Home Assistant VM (HAOS)
├── adguard-container.tf         # AdGuard LXC container
├── docker-container.tf          # Docker/NPM LXC container
├── tailscale-container.tf       # Tailscale LXC container
├── vaultwarden-container.tf     # Vaultwarden LXC container
├── backup.tf                    # Backup job configurations
├── proxmox-storage.tf           # Storage configuration (local-zfs)
├── NETWORK.md                   # Network configuration and static IPs
├── README.md                    # This file
├── RECOVERY.md                  # Disaster recovery procedures
├── .gitignore                   # Protect sensitive data
├── docker/                      # Docker compose files (reference copies)
│   ├── README.md                # Docker services documentation
│   ├── arcane/                  # Arcane orchestrator config
│   ├── frigate/                 # Frigate NVR (not deployed)
│   ├── immich/                  # Immich photo backup (not deployed)
│   └── .../                     # Per-service compose files
├── docs/                        # Additional documentation
│   ├── adguard-dns-records.md
│   ├── download-pipeline-troubleshooting.md
│   ├── home_assistant-static-ip.md
│   ├── npm-config.md
│   ├── bluetooth-ceiling-fan-setup.md
│   ├── media-stack-config.md
│   └── .../
├── ha-config/                   # Home Assistant configuration
│   ├── configuration.yaml
│   ├── automations.yaml
│   └── ...
└── scripts/                     # Utility scripts
    ├── set-static-ips.sh
    ├── deploy-arcane.sh
    ├── deploy-media-stack.sh
    ├── cleanup-backups.sh
    ├── check-router-dns.sh
    └── sonarr-healthcheck.sh
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

### 2b. Terraform State Backend (Garage S3)

State is stored in [Garage](https://garagehq.deuxfleurs.fr/) (S3-compatible object storage) running on LXC 101 at `http://192.168.1.142:3900`.

**If `terraform plan` fails with `AccessDenied` or `key doesn't exist`:**

1. The Garage `.env` on LXC 101 has the **source of truth** credentials:
   ```bash
   ssh root@192.168.1.134 "pct exec 101 -- cat /root/docker/arcane/data/projects/garage/.env"
   ```
2. Sync the credentials to your local `~/.aws/credentials`:
   ```bash
   ./scripts/setup-garage-state.sh --fix-creds
   ```
3. Verify:
   ```bash
   terraform plan
   ```

The `setup-garage-state.sh` script handles:
- **Default mode** (`--fix-creds`): Sync Garage credentials to `~/.aws/credentials`
- **Rotation** (`--rotate-creds`): Generate new keys, update `.env` + `~/.aws/credentials`
- **Rotation also** warns if `~/.aws/credentials` [default] profile doesn't match Garage

```bash
# Quick verify
./scripts/setup-garage-state.sh

# Fix local credentials
./scripts/setup-garage-state.sh --fix-creds

# Rotate keys (if compromised)
./scripts/setup-garage-state.sh --rotate-creds
```

### 3. Create a new container:

- Copy `new-container-example.tf` to a new file or edit it
- Update `vm_id` (use an unused ID), `hostname`, and configuration
- Run:
  ```bash
  terraform plan
  terraform apply
  ```

## Existing Containers (Managed by Terraform)

The following containers and VMs are **fully managed** by Terraform:

| ID  | Name      | Description | Static IP | Terraform File |
|-----|------------|-------------|-----------|----------------|
| 100 | home_assistant | Home Assistant VM (HAOS) - 2 cores, 4GB RAM, 32GB disk | 192.168.1.100 | `home_vm.tf` |
| 101 | docker    | Docker host — media stack + NPM + Arcane — 2 cores, 6GB RAM, 150GB disk, iGPU passthrough | 192.168.1.142 | `docker-container.tf` |
| 102 | tailscale  | Tailscale VPN connectivity - 1 core, 512MB RAM, 2GB disk | 192.168.1.102 | `tailscale-container.tf` |
| 103 | adguard   | AdGuard Home DNS ad-blocker - 1 core, 512MB RAM, 2GB disk | 192.168.1.2 | `adguard-container.tf` |
| 104 | vaultwarden | Vaultwarden password manager (Alpine) - 1 core, 512MB RAM, 4GB disk | 192.168.1.144 | `vaultwarden-container.tf` |

**All services use static IPs configured in Proxmox/LXC/VM configs. See [NETWORK.md](./NETWORK.md) for complete network documentation.**

## Importing Containers

If you need to import an existing container (e.g., after recreating the Proxmox host):

```bash
# Import (find the resource name in state or .tf files)
terraform import proxmox_virtual_environment_container.docker prxhp136/101

# Verify
terraform show
```

**Best Practices:**
- Run `terraform plan` before `apply` to detect any unintended replacements
- Apply changes incrementally to catch issues early
- Use provider v0.76.0+

## Firewall Configuration ✅

The firewall is **enabled with permissive ACCEPT policies** to avoid breaking existing services. See [Issue #3](https://github.com/Darth-ATA/homelab-hp136/issues/3) for implementation details.

### Status (2026-06-18)
- ✅ Cluster-level firewall enabled
- ✅ Security groups created (mgmt, dns, web, home_assistant, tailscale, vaultwarden)
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
| `home_assistant` | Home Assistant UI | 192.168.1.100 | 8123 |
| `tailscale` | Tailscale direct connections | 192.168.1.102 | 41641/udp |
| `vaultwarden` | Vaultwarden HTTP | 192.168.1.144 | 8000 |

### Services & Ports

| Service | IP | Open Ports | Notes |
|---------|-----|------------|-------|
| Proxmox Host | 192.168.1.134 | 8006 (UI), 22 (SSH) | Permissive (future: restrict to management IPs) |
| Home Assistant (VM 100) | 192.168.1.100 | 8123 | VM managed via Terraform ✅ |
| Docker/NPM (LXC 101) | 192.168.1.142 | 80, 443, 81 | NPM reverse proxy |
| Docker — *arr suite | 192.168.1.142 | 7878, 8989, 8686, 9696, 6767 | Radarr, Sonarr, Lidarr, Prowlarr, Bazarr |
| Docker — Deluge | 192.168.1.142 | 8112, 6881 | Torrent client (no VPN) |
| Docker — Jellyfin | 192.168.1.142 | 8096 | Media server |
| Vaultwarden (LXC 104) | 192.168.1.144 | 8000 | Password manager (behind NPM at vw.hp136.duckdns.org) |
| Docker — Arcane | 192.168.1.142 | 3552 | Service orchestrator |
| Tailscale (LXC 102) | 192.168.1.102 | 41641/UDP | Optional direct connections |
| AdGuard (LXC 103) | 192.168.1.2 | 53/tcp+udp | DNS server |

### Firewall Files
- `firewall.tf` - Cluster firewall, security groups, and rules
- `ha-config/home_assitant-vm.tf` - Home Assistant VM (HAOS) configuration and firewall options

### Future Hardening

A follow-up issue will restrict SSH and Proxmox UI to management IPs only, and potentially implement VLAN for IoT devices.

## Notable Infrastructure Workarounds

### Bluetooth USB Passthrough (VM 100)

The N100 has a built-in Realtek Bluetooth Radio (0bda:c821) used by Home Assistant for BLE devices.

**Workaround:** The Proxmox API token can't pass real USB devices (root-only operation). The `usb` block in `home_vm.tf` is declared with `ignore_changes = [usb]`, and a `null_resource` with `local-exec` via SSH applies the actual `qm set` command.

**Host config:** `btusb` is blacklisted via `/etc/modprobe.d/blacklist-btusb.conf` to release the device from the host kernel so it can be passed to the VM.

See `docs/bluetooth-ceiling-fan-setup.md` for the full step-by-step guide.

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
| Home Assistant | 100 | Daily 21:00 | local (dir) | Keep last 5 |
| docker | 101 | Daily 03:00 | local (dir) | Keep daily + monthly (excludes `/data`) |
| tailscale | 102 | Daily 03:45 | local (dir) | Keep daily + monthly |
| adguard | 103 | Daily 04:00 | local (dir) | Keep daily + monthly |
| vaultwarden | 104 | Daily 04:15 | local (dir) | Keep daily + monthly |

**Note:** Docker backup excludes `/data` (media + torrents) to save space. Schedules are staggered off-peak to avoid I/O contention.

**Note:** All backups use `local` (dir-type storage) which supports the backup content type. ZFS zpool storage (`local-zfs`) does NOT support backup content type.

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
| `local` (dir) | Directory | 468GB | ~103GB (31%) | 236GB | Proxmox ISOs, templates, VM 100 backups, container backups |
| `local-zfs` (zfs) | ZFS pool | 370GB | ~114GB (31%) | 236GB | Container disks (101: 150G, 102: 2G, 103: 2G), VM 100 disk |

> **Note:** local-zfs usage increased mainly due to docker container's 150GB disk with media stack data (torrents, media library).

### Why `local-zfs` for Container Disks
- **ZFS compression** reduces actual disk usage for container disk images
- Better performance for container workloads
- Container disks stored on `local-zfs` ✓
- **Note:** Backups must use `local` (dir-type) storage as ZFS pools do NOT support backup content type

### VM 100 (Home Assistant) Backup Storage
Currently, HAOS backups are stored on `local` (dir-type storage). This is the correct configuration as `local-zfs` (ZFS pool) does NOT support the backup content type.

**Note:** Do NOT move backups to `local-zfs` as ZFS pools only support `images` and `rootdir` content types.

**To verify backup storage via CLI:**
```bash
# Check current backup jobs
ssh root@192.168.1.134 "cat /etc/pve/jobs.cfg"

# Run a test backup to local storage
ssh root@192.168.1.134 "vzdump 100 --storage local --mode snapshot"
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
| docker (101) | **150GB** | Sufficient for Docker stack + media library. Monitor `/data` usage — if media grows, expand. |
| tailscale (102) | 2GB | Sufficient for Tailscale only |
| adguard (103) | 2GB | Sufficient for DNS |
| vaultwarden (104) | 4GB | Sufficient for small password database |

### Restore Procedures

See [RECOVERY.md](./RECOVERY.md) for detailed restore instructions.
