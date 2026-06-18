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

| ID | Name | Type | IP | Specs |
|----|------|------|-----|-------|
| 100 | home_assistant | VM | 192.168.1.100 | 2 cores, 4GB RAM, 32GB disk |
| 101 | docker | LXC | 192.168.1.142 | 2 cores, 6GB RAM, **150GB** disk, iGPU passthrough |
| 102 | tailscale | LXC | 192.168.1.102 | 1 core, 512MB RAM, 2GB disk |
| 103 | adguard | LXC | 192.168.1.2 | 1 core, 512MB RAM, 2GB disk |

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
- `NETWORK.md` - Network configuration details (IPs, MACs, services, Frigate)
- `RECOVERY.md` - Disaster recovery and backup restore procedures
- `docker/README.md` - Docker services documentation (Arcane-managed stack)
- `docs/download-pipeline-troubleshooting.md` - Sonarr/Prowlarr/Deluge fix guide
- `docs/bluetooth-ceiling-fan-setup.md` - FanLamp Pro BLE setup guide
- `scripts/` - Utility scripts (deploy, backup, monitoring)

## Important Notes

1. **NEVER commit credentials** - terraform.tfvars and .env files are gitignored
2. **Check .claude/rules.md** for NPM documentation requirements
3. **Container disks are on local-zfs**, backups go to `local` (dir storage)
4. **Services are managed via Arcane** (`/root/docker/arcane/`) on LXC 101, not raw docker-compose
5. **Torrent client is Deluge** (not qBittorrent), **no VPN**

## Bluetooth Passthrough (VM 100)

- **Device:** Realtek Bluetooth Radio (0bda:c821, RTL8821C), built-in on N100
- **Purpose:** FanLamp Pro ceiling fan BLE control via `ble_adv` custom component in HA
- **Host config:** `btusb` blacklisted via `/etc/modprobe.d/blacklist-btusb.conf` (needs initramfs rebuild + reboot)
- **Terraform note:** USB passthrough declared in `home_vm.tf` with `ignore_changes = [usb]` because API token can't pass real USB devices (root-only). Both usb0 (Zigbee) and usb1 (Bluetooth) are set via `null_resource` with `local-exec` via SSH.
- **Ha-ble-adv:** Installed via HACS, config via Duplicate Config method (FanLamp Pro app)
- **Full guide:** `docs/bluetooth-ceiling-fan-setup.md`