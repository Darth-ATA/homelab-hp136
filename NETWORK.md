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

| Service | Type | ID | IP Address | MAC Address | Hostname | Notes |
|---------|------|-----|------------|-------------|----------|-------|
| **Proxmox Host** | Physical | - | 192.168.1.134 | — | `prxhp136` | Proxmox VE management (pve-manager/9.2.3) |
| **Home Assistant** | VM | 100 | 192.168.1.100 | `02:8D:AB:80:C0:9D` | `haos-17.1` | Home automation |
| **Docker/NPM/Arcane** | LXC | 101 | 192.168.1.142 | `BC:24:11:C5:96:4F` | `docker` | 2 cores, 6GB RAM, 150GB disk, iGPU passthrough |
| **Tailscale** | LXC | 102 | 192.168.1.102 | `BC:24:11:CA:68:89` | `tailscale` | VPN |
| **AdGuard Home** | LXC | 103 | 192.168.1.2 | `BC:24:11:D5:A2:77` | `adguard` | DNS ad-blocking |

## Service Access Points

| Service | URL | Config Location |
|---------|-----|----------------|
| Proxmox Web UI | `https://192.168.1.134:8006` | Proxmox host |
| Home Assistant | `http://192.168.1.100:8123` | VM 100 (HA OS) |
| Nginx Proxy Manager | `http://192.168.1.142:81` | Docker container in LXC 101 |
| Arcane | `http://192.168.1.142:3552` | Docker container in LXC 101 (service orchestrator) |
| Vaultwarden | `https://vw.hp136.duckdns.org` | Docker, port 8080 (proxied via NPM) |
| AdGuard Home | `http://192.168.1.2` | LXC 103 |
| Tailscale | `http://192.168.1.102` | LXC 102 |
| Sonarr | `http://192.168.1.142:8989` | Docker (managed via Arcane) |
| Radarr | `http://192.168.1.142:7878` | Docker (managed via Arcane) |
| Lidarr | `http://192.168.1.142:8686` | Docker (managed via Arcane) |
| Prowlarr | `http://192.168.1.142:9696` | Docker (managed via Arcane) |
| Bazarr | `http://192.168.1.142:6767` | Docker (managed via Arcane) |
| Deluge | `http://192.168.1.142:8112` | Docker (managed via Arcane) |
| Jellyfin | `http://192.168.1.142:8096` | Docker (managed via Arcane) |

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

### LXC Containers (101, 102, 103)

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

## Router Configuration

Router access: `http://192.168.1.1` (credentials on router sticker)

### DHCP Settings (requerido para evitar conflictos)

El pool DHCP del router debe **excluir** todas las IPs estáticas del homelab:

| Campo | Valor |
|-------|-------|
| Pool inicio | `192.168.1.150` |
| Pool fin | `192.168.1.254` |
| Máscara | `255.255.255.0` |
| Gateway | `192.168.1.1` |
| Tiempo de concesión | `1440` min (default) |

**IPs estáticas fuera del pool:** `.2` (AdGuard), `.100` (HA), `.102` (Tailscale), `.134` (Proxmox), `.142` (Docker)

### DNS Settings (requerido para que funcione la resolución)

Los dispositivos deben recibir AdGuard como DNS. **NO apuntar a IPs sin servidor DNS** (ej: una cámara IP o alarma).

| Campo | Valor |
|-------|-------|
| DNS primario | `192.168.1.2` (AdGuard) |
| DNS secundario | `192.168.1.2` (o dejarlo vacío) |

### Troubleshooting — Problema detectado (Mayo 2026)

**Síntoma:** Dispositivos WiFi no conectaban correctamente, IPs conflictivas.

**Causa raíz:**
1. El pool DHCP original usaba `.128-254`, pisando IPs estáticas (`.134`, `.142`)
2. El DNS del router apuntaba a `192.168.1.136` (alarma o cámara IP), que **no tiene servidor DNS** — los dispositivos recibían un DNS que no respondía y fallaban al resolver dominios

**Fix:** Ajustar pool DHCP a `.150-254` y DNS a `192.168.1.2`.

## DHCP Range

Reserve `192.168.1.150-254` for DHCP clients on your router to avoid conflicts with static homelab IPs.

## Notes

- All static IPs use `/24` subnet (255.255.255.0)
- Gateway for all devices: `192.168.1.1` (your router)
- All devices should use AdGuard (`192.168.1.2`) as DNS server — configure this ON THE ROUTER so DHCP clients receive it automatically
- `.local` domains may conflict with mDNS - prefer using `.home` domains

## Frigate NVR (NOT deployed)

Frigate is **configured but not currently running** on LXC 101. The compose file and config exist on the host at `/root/docker/frigate/`.

**Why not deployed:** The Dahua camera (192.168.1.108) requires authentication setup and OpenVINO GPU passthrough validation.

**To deploy when ready:**

```bash
# 1. Set FRIGATE_RTSP_PASSWORD in docker/.env
# 2. Install Intel OpenCL runtime:
ssh root@192.168.1.142 "apt install -y intel-opencl-icd intel-igc-cm && groupadd -g 44 video && usermod -aG video root"

# 3. Start Frigate:
ssh root@192.168.1.134 "pct exec 101 -- docker compose -f /root/docker/frigate/compose.yml up -d"

# 4. View logs:
ssh root@192.168.1.134 "pct exec 101 -- docker logs frigate -f"
```

**Access when running:** http://192.168.1.142:5000

### Camera — Dahua IPC-HDW2230T-AS-S2

| Property | Value |
|----------|-------|
| IP | `192.168.1.108` |
| RTSP port | `554` |
| Auth | Digest (no Basic) |
| RTSP path (sub/main) | `/live` |
| Streaming user | `admin` |

### Known issues

- **Camera IP lock:** The Dahua blocks IPs after 5 failed auth attempts (`General.LockLoginEnable=true`). If Frigate shows auth errors, disable via CGI:
  ```bash
  curl --digest -u admin:<password> 'http://192.168.1.108/cgi-bin/configManager.cgi?action=setConfig&General.LockLoginEnable=false'
  ```
- **OpenVINO model shape:** The bundled model expects 300×300 input. If you see a shape broadcast error, verify `model.width: 300`, `model.height: 300` in config.
- **go2rtc env limitation:** Frigate's bundled go2rtc v1.9.10 does not support `${VAR}` in stream URLs. Use `{{ VAR }}` Jinja2 syntax via `config.yml.j2` which Frigate's Python runtime resolves before passing to go2rtc.
- **Cam connection:** Frigate uses `network_mode: host` to avoid Docker bridge routing issues with RTSP multicast.
