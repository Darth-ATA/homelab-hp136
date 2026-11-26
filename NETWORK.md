# Network Configuration

This document describes the network configuration for the homelab Proxmox host and all services.

## Subnet Contract

- **LAN subnet:** `10.10.10.0/24` (gateway `.1`, DNS `.2` at AdGuard)
- **Single source of truth:** Terraform `locals.tf` (`subnet_base` + `node_ips` last octets). All `*.tf` IPs, firewall destinations, and this allocation table derive from it — no hardcoded IP literals in Terraform.
- **Fallback:** if the router ever rejects a 10.x LAN, switch `locals.subnet_base` to `192.168.77` (identical last octets) plus the `main.tf` backend endpoint literal.
- **DHCP:** documented router pool is `.150`–`.254`. The host and guest addresses are outside it; the documented camera address (`.200`) is inside it.
- **Renumber procedure:** `docs/tailscale-derp-runbook.md`.

## Proxmox Host

| Property | Value |
|----------|-------|
| Hostname | `prxhp136` |
| IP Address | `10.10.10.134/24` |
| Gateway | `10.10.10.1` |
| DNS | `10.10.10.2` (AdGuard) |
| SSH Access | `ssh -i ~/.ssh/homelab_key root@10.10.10.134` |

**Config file:** `/etc/network/interfaces` on Proxmox host

## Static IP Assignments

All services use static IPs to ensure DNS resolution and proxy configurations don't break on reboot.

| Service | Type | ID | IP Address | MAC Address | Hostname | Notes |
|---------|------|-----|------------|-------------|----------|-------|
| **Proxmox Host** | Physical | - | 10.10.10.134 | — | `prxhp136` | Proxmox VE management (pve-manager/9.2.3) |
| **Home Assistant** | VM | 100 | 10.10.10.100 | `02:8D:AB:80:C0:9D` | `haos-17.1` | Home automation |
| **Docker/NPM/Arcane** | LXC | 101 | 10.10.10.142 | `BC:24:11:C5:96:4F` | `docker` | 2 cores, 6GB RAM, 150GB disk, iGPU passthrough |
| **Tailscale** | LXC | 102 | 10.10.10.102 | `BC:24:11:CA:68:89` | `tailscale` | VPN |
| **AdGuard Home** | LXC | 103 | 10.10.10.2 | `BC:24:11:D5:A2:77` | `adguard` | DNS ad-blocking |
| **Vaultwarden** | LXC | 104 | 10.10.10.144 | `BC:24:11:78:83:C3` | `alpine-vaultwarden` | Password manager |
| **Jellyfin** | LXC | 105 | 10.10.10.145 | `BC:24:11:46:95:DE` | `jellyfin` | Media server (native, not Docker), iGPU passthrough |
| **Dahua IPC-HDW2230 Camera** | Physical | - | 10.10.10.200 | `C4:AA:C4:1F:D2:F0` | `dahua-cam` | PoE camera — verify reservation/exclusion; `.200` overlaps documented DHCP pool |

## Network security review

**Scope:** repository configuration, not a live audit. `locals.tf` selects `10.10.10.0/24`; the `192.168.1.134` in issue #7 is the legacy host address. Migration staging is off by default in `variables.tf`. No guest VLAN tag or host VLAN interface is declared.

```text
Internet --- edge router (.1; WAN rules not in Terraform)
                |
                +-- LAN clients and IP camera
                |
                +-- nic0 / vmbr0 --- Proxmox management (.134)
                               |
                               +-- VM 100 HA --- USB Zigbee and Bluetooth radios
                               +-- CT 101 Docker (NPM, Arcane, Garage, media, SMB)
                               +-- CT 102 Tailscale subnet router <-- tailnet peers
                               +-- CT 103 AdGuard DNS
                               +-- CT 104 Vaultwarden
                               +-- CT 105 Jellyfin
```

- **IP and MAC policy:** Keep the pinned primary LXC MACs for repeatable restores and consistent router inventory. HA's MAC in the allocation table is documented in the [HA addressing notes](docs/ha-static-ip-dhcp-reservation.md), not fixed in `home_vm.tf`; check it after recreation. A static IP does not require a fixed MAC, and a MAC is not an access control. Randomizing stationary guests adds churn without isolating them. Check the camera address against the router leases and exclusions before assigning it elsewhere.
- **Inbound exposure:** The [router cutover runbook](docs/tailscale-derp-runbook.md) calls for a forward to slskd on CT 101 (TCP 50300); the [slskd integration spec](openspec/specs/soularr-integration/spec.md) describes outbound-only operation. Neither proves the current router rule. Check static forwards, UPnP mappings, exposed-host mode and IPv6 ingress policy. Check NPM host access lists too: forwarding 80/443 could publish Arcane, NPM itself or other administrative upstreams. A DNS record or wildcard certificate is not evidence of public access. Keep management, DNS, SMB and Garage off the public Internet.
- **Lateral access:** Guests share a broadcast domain. Traffic between neighbors need not cross the router. The [cluster rules](firewall.tf) default to ACCEPT, with no source limit in the management group; guest NIC filtering is disabled in the checked-in definitions. Tailscale also advertises the LAN: review route approval and tailnet grants separately from WAN NAT. Before enforcing guest rules, identify trusted management sources and required flows (including NPM to backends and Terraform clients to Garage).

### Proposed segmentation (not deployed)

| Zone | Intended access at the routing firewall |
|------|-----------------------------------------|
| Existing trusted LAN | Keep Proxmox management and HA here initially. Only trusted admins should reach management UIs. |
| IoT VLAN | Put Ethernet/Wi-Fi IoT endpoints such as the camera here. Deny new connections to the trusted LAN by default. Permit DNS to AdGuard and DHCP to the IoT gateway; allow HA or the NVR to initiate only required device connections (e.g. RTSP to the camera), with stateful replies. Limit Internet egress to documented device needs. |
| Optional DMZ | Only if inbound public service is required: separate the ingress proxy from the multi-service Docker CT. Permit approved WAN ports to the proxy and only named upstreams/ports from it to the LAN. Never place CT 101 wholesale in a router's exposed-host mode. Otherwise prefer tailnet-only access. |

Zigbee, Z-Wave and Bluetooth radio traffic is not Ethernet; a VLAN cannot isolate devices on a USB coordinator. Keep HA single-homed. Test IP integrations across the routed boundary; enable a scoped discovery relay only for integrations that require multicast.

**Implementation gate:** Confirm router inter-VLAN ACLs, switch trunk/access-port support and AP SSID-to-VLAN mapping where Wi-Fi is needed. The owner must select an unused VLAN ID, non-overlapping subnet, DHCP scope and permitted flows. A router/switch-only camera VLAN needs no Proxmox interface. If guests later join it, carry the tag on a VLAN-aware `vmbr0` trunk and tag only their NICs; a `vmbr0.<tag>` interface is needed only if the host itself needs an address there. Keep the management path unchanged. Before a Terraform change, save current network settings, arrange local console rollback and pilot one IP device; verify DNS, HA control, blocked IoT-to-management access and continued access to the state backend.

## Service Access Points

| Service | URL | Config Location |
|---------|-----|----------------|
| Proxmox Web UI | `https://10.10.10.134:8006` | Proxmox host |
| Home Assistant | `http://10.10.10.100:8123` | VM 100 (HA OS) |
| Nginx Proxy Manager | `http://10.10.10.142:81` | Docker container in LXC 101 |
| Arcane | `http://10.10.10.142:3552` | Docker container in LXC 101 (service orchestrator) |
| Vaultwarden | `https://vw.hp136.duckdns.org` | LXC 104 (Alpine), port 8000 (proxied via NPM) |
| AdGuard Home | `http://10.10.10.2` | LXC 103 |
| Tailscale | `http://10.10.10.102` | LXC 102 |
| Sonarr | `http://10.10.10.142:8989` | Docker (managed via Arcane) |
| Radarr | `http://10.10.10.142:7878` | Docker (managed via Arcane) |
| Lidarr | `http://10.10.10.142:8686` | Docker (managed via Arcane) |
| Prowlarr | `http://10.10.10.142:9696` | Docker (managed via Arcane) |
| Bazarr | `http://10.10.10.142:6767` | Docker (managed via Arcane) |
| Deluge | `http://10.10.10.142:8112` | Docker (managed via Arcane) |
| Garage (S3 API) | `http://10.10.10.142:3900` | Docker container in LXC 101 (managed via Arcane) — Terraform state backend |
| Garage (RPC) | `http://10.10.10.142:3901` | Garage cluster/internal RPC |
| Garage (Web UI) | `http://10.10.10.142:3902` | Garage web interface |
| Garage (Admin API) | `http://10.10.10.142:3903` | Garage admin API |
| Jellyfin | `http://10.10.10.145:8096` | LXC 105 (native, Ubuntu 24.04, iGPU passthrough) |
| Navidrome | `http://10.10.10.142:4533` | Docker (managed via Arcane) — Subsonic/MPD-compatible music streaming |
| | `https://music.hp136.duckdns.org` | Proxied via NPM with SSL (wildcard cert) |
| slskd | `http://10.10.10.142:5030` | Docker (managed via Arcane) — Soulseek P2P music discovery |
| | `http://10.10.10.142:50300` | slskd DHT/listening port |
| Soularr | `http://10.10.10.142:8265` | Docker (managed via Arcane) — syncs Soulseek downloads to Lidarr |
| Flaresolverr | `http://10.10.10.142:8191` | Docker (managed via Arcane) — Cloudflare bypass proxy for Prowlarr |

## DNS Configuration

**AdGuard Home** (`10.10.10.2`) manages local DNS records:

| Domain | Points To | Purpose |
|--------|-----------|---------|
| `homeassistant.local` | `10.10.10.142` | Proxied via NPM to HA |
| `homeassistant.home` | `10.10.10.142` | Alternative domain (recommended) |
| `adguard.local` | `10.10.10.2` | AdGuard admin panel |
| `adguard.home` | `10.10.10.2` | Alternative domain |
| `npm.local` | `10.10.10.142` | NPM admin panel |
| `npm.home` | `10.10.10.142` | Alternative domain |

**To use:** Set your device's DNS server to `10.10.10.2`

## Nginx Proxy Manager Configuration

All domains use the wildcard SSL certificate `*.hp136.duckdns.org` (Let's Encrypt, via NPM). Proxy hosts configured in NPM (http://10.10.10.142:81):

| Domain | Forward To | Port | Notes |
|--------|------------|------|-------|
| `homeassistant.local` / `homeassistant.home` | `10.10.10.100` | 8123 | Websockets ✅ |
| `ha.hp136.duckdns.org` | `10.10.10.100` | 8123 | Home Assistant |
| `agh.hp136.duckdns.org` | `10.10.10.2` | 80 | AdGuard admin |
| `arcan.hp136.duckdns.org` | `10.10.10.142` | 3552 | Arcane orchestrator |
| `npm.hp136.duckdns.org` | `10.10.10.142` | 81 | NPM admin panel |
| `vw.hp136.duckdns.org` | `10.10.10.144` | 8000 | Vaultwarden |
| `music.hp136.duckdns.org` | `10.10.10.142` | 4533 | Navidrome |
| `son.hp136.duckdns.org` | `10.10.10.142` | 8989 | Sonarr |
| `rad.hp136.duckdns.org` | `10.10.10.142` | 7878 | Radarr |
| `lidarr.hp136.duckdns.org` | `10.10.10.142` | 8686 | Lidarr |
| `prowlarr.hp136.duckdns.org` | `10.10.10.142` | 9696 | Prowlarr |
| `bazarr.hp136.duckdns.org` | `10.10.10.142` | 6767 | Bazarr |
| `deluge.hp136.duckdns.org` | `10.10.10.142` | 8112 | Deluge |
| `jelly.hp136.duckdns.org` | `10.10.10.145` | 8096 | Jellyfin |
| `frigate.hp136.duckdns.org` | `10.10.10.142` | 5000 | ⚠️ Not deployed — configured for future use |

## How to Recreate Static IPs

### LXC Containers (101, 102, 103, 104, 105)

Use `locals.tf` and the corresponding `*-container.tf` network and initialization blocks as the desired configuration. Compare the restored guest's primary NIC, address and gateway with the allocation table before reconnecting it; do not generate a new MAC on each boot.

### Home Assistant VM (100)

Inside HA OS (via Proxmox console or SSH):
```bash
ha network update enp6s18 --ipv4-method static \
  --ipv4-address 10.10.10.100/24 \
  --ipv4-gateway 10.10.10.1 \
  --ipv4-nameserver 10.10.10.2
```

### Proxmox Host

Edit `/etc/network/interfaces`:
```bash
auto vmbr0
iface vmbr0 inet static
    address 10.10.10.134/24
    gateway 10.10.10.1
    bridge-ports nic0
    bridge-stp off
    bridge-fd 0
```

## Router Configuration

Router access: `http://10.10.10.1` (credentials on router sticker)

### DHCP Settings (requerido para evitar conflictos)

El pool DHCP del router debe **excluir** todas las IPs estáticas del homelab:

| Campo | Valor |
|-------|-------|
| Pool inicio | `10.10.10.150` |
| Pool fin | `10.10.10.254` |
| Máscara | `255.255.255.0` |
| Gateway | `10.10.10.1` |
| Tiempo de concesión | `1440` min (default) |

**IPs estáticas fuera del pool:** `.2` (AdGuard), `.100` (HA), `.102` (Tailscale), `.134` (Proxmox), `.142` (Docker), `.144` (Vaultwarden)

### DNS Settings (requerido para que funcione la resolución)

Los dispositivos deben recibir AdGuard como DNS. **NO apuntar a IPs sin servidor DNS** (ej: una cámara IP o alarma).

| Campo | Valor |
|-------|-------|
| DNS primario | `10.10.10.2` (AdGuard) |
| DNS secundario | `10.10.10.2` (o dejarlo vacío) |

### Troubleshooting — Problema detectado (Mayo 2026)

**Síntoma:** Dispositivos WiFi no conectaban correctamente, IPs conflictivas.

**Causa raíz:**
1. El pool DHCP original usaba `.128-254`, pisando IPs estáticas (`.134`, `.142`)
2. El DNS del router apuntaba a `10.10.10.136` (alarma o cámara IP), que **no tiene servidor DNS** — los dispositivos recibían un DNS que no respondía y fallaban al resolver dominios

**Fix:** Ajustar pool DHCP a `.150-254` y DNS a `10.10.10.2`.

## DHCP Range

Reserve `10.10.10.150-254` for DHCP clients on your router to avoid conflicts with static homelab IPs.

## Notes

- All static IPs use `/24` subnet (255.255.255.0)
- Gateway for all devices: `10.10.10.1` (your router)
- All devices should use AdGuard (`10.10.10.2`) as DNS server — configure this ON THE ROUTER so DHCP clients receive it automatically
- `.local` domains may conflict with mDNS - prefer using `.home` domains

## Frigate NVR (NOT deployed)

Frigate is **configured but not currently running** on LXC 101. The compose file and config exist on the host at `/root/docker/frigate/`.

**Why not deployed:** The Dahua camera (10.10.10.200) requires authentication setup and OpenVINO GPU passthrough validation.

**To deploy when ready:**

```bash
# 1. Set FRIGATE_RTSP_PASSWORD in docker/.env
# 2. Install Intel OpenCL runtime:
ssh root@10.10.10.142 "apt install -y intel-opencl-icd intel-igc-cm && groupadd -g 44 video && usermod -aG video root"

# 3. Start Frigate:
ssh root@10.10.10.134 "pct exec 101 -- docker compose -f /root/docker/frigate/compose.yml up -d"

# 4. View logs:
ssh root@10.10.10.134 "pct exec 101 -- docker logs frigate -f"
```

**Access when running:** http://10.10.10.142:5000

### Camera — Dahua IPC-HDW2230

| Property | Value |
|----------|-------|
| IP | `10.10.10.200` |
| MAC | `C4:AA:C4:1F:D2:F0` |
| RTSP port | `554` |
| HTTP port | `80` |
| Auth | Digest (no Basic) |
| RTSP path (sub/main) | `/live` |
| Streaming user | `admin` |
| Connection | POE, wired directly to router |

### Known issues

- **Camera IP lock:** The Dahua blocks IPs after 5 failed auth attempts (`General.LockLoginEnable=true`). If Frigate shows auth errors, disable via CGI:
  ```bash
  curl --digest -u admin:<password> 'http://10.10.10.108/cgi-bin/configManager.cgi?action=setConfig&General.LockLoginEnable=false'
  ```
- **OpenVINO model shape:** The bundled model expects 300×300 input. If you see a shape broadcast error, verify `model.width: 300`, `model.height: 300` in config.
- **go2rtc env limitation:** Frigate's bundled go2rtc v1.9.10 does not support `${VAR}` in stream URLs. Use `{{ VAR }}` Jinja2 syntax via `config.yml.j2` which Frigate's Python runtime resolves before passing to go2rtc.
- **Cam connection:** Frigate uses `network_mode: host` to avoid Docker bridge routing issues with RTSP multicast.
