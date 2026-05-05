# Network Configuration

This document describes the network configuration for the homelab Proxmox host and all services.

## Proxmox Host

| Property | Value |
|----------|-------|
| Hostname | `prxhp136` |
| IP Address | `192.168.1.134/24` |
| Gateway | `192.168.1.1` |
| DNS | `192.168.1.2` (AdGuard) |
| SSH Access | `ssh -i ~/.ssh/homelab_key root@192.168.1.134` |

**Config file:** `/etc/network/interfaces` on Proxmox host

## Static IP Assignments

All services use static IPs to ensure DNS resolution and proxy configurations don't break on reboot.

| Service | Type | ID | IP Address | Hostname | Notes |
|---------|------|-----|------------|----------|-------|
| **Proxmox Host** | Physical | - | 192.168.1.134 | `prxhp136` | Proxmox VE management |
| **Home Assistant** | VM | 100 | 192.168.1.100 | `haos-17.1` | Home automation |
| **Docker/NPM/Arcane** | LXC | 101 | 192.168.1.142 | `docker` | Container runtime + Nginx Proxy Manager + Arcane |
| **Tailscale** | LXC | 102 | 192.168.1.102 | `tailscale` | VPN |
| **AdGuard Home** | LXC | 103 | 192.168.1.2 | `adguard` | DNS ad-blocking |
| **Debian Test** | LXC | 105 | 192.168.1.105 | `debian-test` | Test container |

## Service Access Points

| Service | URL | Config Location |
|---------|-----|----------------|
| Proxmox Web UI | `https://192.168.1.134:8006` | Proxmox host |
| Home Assistant | `http://192.168.1.100:8123` | VM 100 (HA OS) |
| Nginx Proxy Manager | `http://192.168.1.142:81` | Docker container in LXC 101 |
| Arcane | `http://192.168.1.142:3552` | Docker container in LXC 101 |
| Vaultwarden | `https://vw.hp136.duckdns.org` | Docker container in LXC 101 |
| AdGuard Home | `http://192.168.1.2` | LXC 103 |
| Tailscale | `http://192.168.1.102` | LXC 102 |

## DNS Configuration

**AdGuard Home** (`192.168.1.2`) manages local DNS records:

| Domain | Points To | Purpose |
|--------|-----------|---------|
| `homeassistant.local` | `192.168.1.142` | Proxied via NPM to HA |
| `homeassistant.home` | `192.168.1.142` | Alternative domain (recommended) |
| `adguard.local` | `192.168.1.2` | AdGuard admin panel |
| `adguard.home` | `192.168.1.2` | Alternative domain |
| `npm.local` | `192.168.1.142` | NPM admin panel |
| `npm.home` | `192.168.1.142` | Alternative domain |

**To use:** Set your device's DNS server to `192.168.1.2`

## Nginx Proxy Manager Configuration

Proxy hosts configured in NPM (http://192.168.1.142:81):

| Domain | Forward To | Port | Websockets |
|--------|------------|------|------------|
| `homeassistant.local` / `homeassistant.home` | `192.168.1.100` | 8123 | ✅ Enabled |

## How to Recreate Static IPs

### LXC Containers (101, 102, 103, 105)

SSH to Proxmox and edit configs:
```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134

# For each container, edit /etc/pve/lxc/<ID>.conf
# Replace net0 line with:
# net0: name=eth0,bridge=vmbr0,hwaddr=<MAC>,firewall=1,ip=<IP>/24,gw=192.168.1.1,type=veth

# Restart container
pct stop <ID> && pct start <ID>
```

### Home Assistant VM (100)

Inside HA OS (via Proxmox console or SSH):
```bash
ha network update enp6s18 --ipv4-method static \
  --ipv4-address 192.168.1.100/24 \
  --ipv4-gateway 192.168.1.1 \
  --ipv4-nameserver 192.168.1.2
```

### Proxmox Host

Edit `/etc/network/interfaces`:
```bash
auto vmbr0
iface vmbr0 inet static
    address 192.168.1.134/24
    gateway 192.168.1.1
    bridge-ports nic0
    bridge-stp off
    bridge-fd 0
```

## DHCP Range

Reserve `192.168.1.200-250` for DHCP clients on your router to avoid conflicts.

## Notes

- All static IPs use `/24` subnet (255.255.255.0)
- Gateway for all devices: `192.168.1.1` (your router)
- All devices use AdGuard (`192.168.1.2`) as DNS server
- `.local` domains may conflict with mDNS - prefer using `.home` domains
