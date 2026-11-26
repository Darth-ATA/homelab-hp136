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
proxmox_endpoint = "https://10.10.10.134:8006/api2/json"
EOL
```

### 2. Initialize Terraform:

```bash
terraform init
```

### 2b. Terraform State Backend (Garage S3)

State is stored in [Garage](https://garagehq.deuxfleurs.fr/) (S3-compatible object storage) running on LXC 101 at `http://10.10.10.142:3900`.

**If `terraform plan` fails with `AccessDenied` or `key doesn't exist`:**

1. The Garage `.env` on LXC 101 has the **source of truth** credentials:
   ```bash
   ssh root@10.10.10.134 "pct exec 101 -- cat /root/docker/arcane/data/projects/garage/.env"
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

## Guest network inventory

| ID | Guest | Static IP | Primary NIC MAC | Terraform definition |
|----|-------|-----------|-----------------|----------------------|
| 100 | Home Assistant (HAOS) | 10.10.10.100 | `02:8D:AB:80:C0:9D` | `home_vm.tf` (MAC documented, not pinned) |
| 101 | Docker (media, NPM, Arcane) | 10.10.10.142 | `BC:24:11:C5:96:4F` | `docker-container.tf` |
| 102 | Tailscale subnet router | 10.10.10.102 | `BC:24:11:CA:68:89` | `tailscale-container.tf` |
| 103 | AdGuard Home | 10.10.10.2 | `BC:24:11:D5:A2:77` | `adguard-container.tf` |
| 104 | Vaultwarden | 10.10.10.144 | `BC:24:11:78:83:C3` | `vaultwarden-container.tf` |
| 105 | Jellyfin (native) | 10.10.10.145 | `BC:24:11:46:95:DE` | `jellyfin-container.tf` |

See [NETWORK.md](NETWORK.md#static-ip-assignments) for physical devices and addressing.

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

## Firewall Configuration

[`firewall.tf`](firewall.tf) enables the cluster firewall with **ACCEPT** input and output defaults. The groups below permit traffic; they are not a default-deny allowlist. All guest NIC definitions on `vmbr0` set `firewall = false`, including HA despite its enabled VM firewall options. Do not rely on these rules for guest-to-guest isolation.

### Security Groups Defined

| Group | Purpose | Target | Ports |
|-------|---------|--------|-------|
| `mgmt` | Management access (SSH + Proxmox UI) | 10.10.10.134 | 22, 8006 |
| `dns` | AdGuard DNS | 10.10.10.2 | 53/tcp+udp |
| `web` | Docker/NPM services | 10.10.10.142 | 80, 443, 81 |
| `home_assistant` | Home Assistant UI and discovery | 10.10.10.100 | 8123/tcp, 5353/udp, 1900/udp |
| `tailscale` | Tailscale direct connections | 10.10.10.102 | 41641/udp |
| `vaultwarden` | Vaultwarden HTTP | 10.10.10.144 | 8000 |
| `jellyfin` | Jellyfin HTTP | 10.10.10.145 | 8096 |

### Services & Ports

These are **repo-documented LAN endpoints**, not tested listeners or WAN forwards. Ports are TCP unless marked UDP. For Docker, published host and container port numbers match unless an arrow shows otherwise. Compare the [reference Compose files](docker/) with the live Arcane projects before changing access.

| Host | Service | LAN port(s) and purpose |
|------|---------|-------------------------|
| Proxmox | Management | 22 SSH, 8006 UI/API |
| VM 100 | HA | 8123 UI; 5353/UDP mDNS and 1900/UDP SSDP discovery traffic |
| CT 101 | Nginx Proxy Manager (host network) | 80 HTTP, 443 HTTPS proxy; 81 admin |
| CT 101 | Arcane | 3552 admin |
| CT 101 | Garage | 3900 S3 (includes Terraform state), 3901 cluster RPC, 3902 web serving, 3903 admin |
| CT 101 | Samba ([Terraform definition](samba-share.tf)) | 139, 445 SMB for LAN/tailnet clients |
| CT 101 | Media automation | 8989 Sonarr, 7878 Radarr, 8686 Lidarr, 9696 Prowlarr, 6767 Bazarr, 8191 FlareSolverr |
| CT 101 | Deluge | 8112 UI, 58846 daemon, 6881 TCP+UDP peers |
| CT 101 | Music | 4533 Navidrome, 5030 slskd UI, 50300 slskd peers, 8265 Soularr UI |
| CT 101 | Dashboard | 8000 (documented [NPM upstream](docs/npm-config.md)) |
| CT 102 | Tailscale | 41641/UDP direct peer connections |
| CT 103 | AdGuard | 53 TCP+UDP DNS, 80 admin |
| CT 104 | Vaultwarden | 8000 HTTP upstream for NPM |
| CT 105 | Jellyfin | 8096 native HTTP upstream |
| LAN camera | Video | 80 HTTP, 554 RTSP |

Reference-only or inactive deployments on CT 101 are **not evidence of open ports**: qBittorrent (8081 → 8080 UI, 6881 TCP+UDP peers), Immich (2283 → 3001), Frigate (host network, documented UI 5000), and the old Jellyfin Compose (8096, 8920, 7359/UDP, 1900/UDP).

**WAN exposure is unverified.** Publishing a Docker port makes it available on the host interfaces by default; it does not configure the edge router. Conversely, forwarding HTTPS to NPM could expose an admin UI without forwarding its own port. See the [topology, exposure review and proposed isolation policy](NETWORK.md#network-security-review).

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
ssh root@10.10.10.134 "/usr/local/bin/cleanup-backups.sh"

# Check log
ssh root@10.10.10.134 "cat /var/log/backup-cleanup.log"
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
ssh root@10.10.10.134 "cat /etc/pve/jobs.cfg"

# Run a test backup to local storage
ssh root@10.10.10.134 "vzdump 100 --storage local --mode snapshot"
```

**Cleanup old backups (keep last 3-5):**
```bash
# List HAOS backups
ssh root@10.10.10.134 "ls -lht /var/lib/vz/dump/vzdump-qemu-100-*.vma.*"

# Remove old backups (example - adjust dates as needed)
ssh root@10.10.10.134 "rm /var/lib/vz/dump/vzdump-qemu-100-2026_0*"
```

### Cleanup: Unused Templates/ISOs
```bash
# Check what's in templates directory
ssh root@10.10.10.134 "ls -lh /var/lib/vz/template/cache/ /var/lib/vz/template/iso/"

# Remove unused templates (verify first!)
ssh root@10.10.10.134 "rm /var/lib/vz/template/cache/<unused-template>.tar.gz"
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
