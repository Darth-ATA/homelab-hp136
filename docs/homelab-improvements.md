# Homelab Improvement Roadmap

Priorities: 🔴 Crítico | 🟡 Alta | 🟢 Media | ⚪ Baja

---

## 🚀 Completado

- [x] **API keys expuestas en docs** — Reemplazadas por placeholders en `docs/download-pipeline-troubleshooting.md` y `docs/torrentio-setup.md`. PR #35.

---

## 🔴 Crítico

### 1. ~~qBittorrent sin VPN~~ → Cliente único sin VPN

**Decisión tomada:** Se eligió **Deluge** como cliente único. qBittorrent y Gluetun fueron removidos. No hay VPN.

**Implicaciones:**
- Tráfico P2P sale por IP real (192.168.1.142)
- Ya no hay contención de puertos entre Deluge/qBittorrent
- `/dev/net/tun` ya no es necesario en LXC 101

**Si en futuro se quiere VPN:** Agregar Gluetun con network_mode: service:gluetun al Deluge, o cambiar a qBittorrent+WireGuard.

---

### 2. Firewall permisivo

**Problema:** `input_policy = "ACCEPT"` y `output_policy = "ACCEPT"`. Cualquier dispositivo en la red local puede alcanzar SSH (22), Proxmox UI (8006), NPM admin (81).

**Qué hacer:**
- Cambiar `input_policy` a `DROP`
- Agregar `source` en las reglas del security group `mgmt` con tus IPs de management
- Tener consola a mano por si hay lockout

**Documentación:** `FIREWALL-HARDENING-ISSUE.md` ya tiene el plan detallado.

---

### 3. Jellyfin sin aceleración por hardware

**Problema:** El LXC 101 tiene `/dev/dri/card0` y `/dev/dri/renderD128` passthrough, pero los devices en `docker/jellyfin/compose.yml` están comentados. Se transcodea por CPU en un N100 con iGPU Intel.

**Qué hacer:** Descomentar los devices en el compose de Jellyfin y agregar al environment `JELLYFIN_FFMPEG__hardwareAccelerationType: "vaapi"`.

---

### 4. Monitoreo cero

**Problema:** No hay métricas de disco, CPU, RAM, ni estado de servicios. Frigate graba 24/7 y no hay alertas de espacio.

**Soluciones (elegir una):**
- **Ligero:** Netdata en el LXC 101 (`docker run -d --name=netdata ...`)
- **Medio:** Prometheus + Node Exporter + Grafana
- **Mínimo:** Script que checkea disco y manda alerta por Telegram (similar a `check-router-dns.sh`)

---

### 5. 15+ servicios en un solo LXC con 2 cores

**Problema:** NPM, Vaultwarden, qBittorrent, \*arrs, Jellyfin, Immich (5 containers), Frigate, etc. compitiendo por 2 cores y 6GB RAM. Frigate + Immich ML + Jellyfin transcoding pelean por la iGPU.

**Qué hacer:**
- **Corto plazo:** Agregar `deploy.resources.limits` a los compose files para evitar que un servicio se coma todo
- **Largo plazo:** Mover Frigate o Immich a su propio LXC

---

## 🟡 Alta

### 6. Red plana sin segmentación

**Problema:** Todo en `vmbr0` — cámara IP (108), HA, Vaultwarden, torrent client. Si comprometen un servicio, la red completa es accesible.

**Qué hacer:** Crear VLANs en Proxmox:
- VLAN 10: IoT (cámara, dispositivos HA)
- VLAN 20: Servicios críticos (Vaultwarden, NPM)
- Configurar reglas de firewall entre VLANs

---

### 7. Offsite backup inexistente

**Problema:** Todos los backups en `local` (mismo disco físico). Si el N100 muere, se pierde todo.

**Qué hacer:**
- **Mínimo:** Vaultwarden (`vw-data`) backup a S3/Backblaze vía `rclone`
- **Medio:** Terraform state backup externo + script de dump de Vaultwarden
- **Ideal:** Backup completo de Proxmox a storage externo (USB, NAS, o cloud)

---

### 8. Backups sin verificar

**Problema:** Los backups se ejecutan pero nunca se testea una restauración real.

**Qué hacer:** Agregar tarea calendar (manual) para:
- Restaurar container 102 (tailscale) a un ID temporal, verificar que funciona, destruirlo
- Documentar el resultado

---

### 9. Docker updates manuales

**Problema:** Ningún container se actualiza automáticamente.

**Qué hacer:** Agregar Watchtower al stack (`docker-compose` aparte):
```yaml
services:
  watchtower:
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
```

O Diun para solo recibir notificaciones de nuevas imágenes sin actualizar automáticamente.

---

### 10. ~~Deluge + qBittorrent duplicados~~ → Resuelto

**Decisión tomada:** Se eliminó qBittorrent. Solo Deluge corre como cliente de torrents. Sin VPN.

---

## 🟢 Media

### 11. Immich sin aceleración ML

**Problema:** Immich Machine Learning procesa fotos por CPU. Podría usar la iGPU para reconocimiento facial.

**Qué hacer:** Agregar `/dev/dri:/dev/dri` al container `immich-machine-learning` y configurar `IMMICH_MACHINE_LEARNING__MODEL__DEVICE: "openvino"`.

---

### 12. NPM sin backup de config

**Problema:** Existe `docker/npm/recovery.sh` pero no está documentado ni testeado su funcionamiento.

**Qué hacer:** Verificar que `recovery.sh` funciona, documentar en `docs/npm-config.md`.

---

### 13. Makefile infrautilizado

**Problema:** Solo tiene targets de Frigate y Terraform. Faltan comandos comunes.

**Qué hacer:** Agregar targets para:
- `make ps` — docker ps via SSH
- `make logs SERVICE=<name>` — logs de un servicio
- `make disk` — df -h del LXC
- `make backup-status` — últimos backups
- `make update` — docker compose pull + up -d

---

### 14. Frigate sin cleanup automático de recordings

**Problema:** Las grabaciones se acumulan sin límite. Hoy solo hay cleanup manual.

**Qué hacer:** Configurar `record.retain.days` en la config de Frigate, o agregar un cron en el LXC que limpie recordings viejos.

---

## ⚪ Baja

### 15. Terraform state en git no ignorado correctamente

Los `.tfstate` están en `.gitignore` pero hay backups locales (`terraform.tfstate.1780068606.backup`) en el working directory.

---

## Implementación Sugerida

| Sprint | Items                                                | Esfuerzo |
| ------ | ---------------------------------------------------- | -------- |
| 1      | #1 Gluetun + #2 Firewall                             | Medio    |
| 2      | #3 Jellyfin HW + #4 Monitoreo                        | Medio    |
| 3      | #5 Límites de recursos + #9 Watchtower               | Bajo     |
| 4      | #6 VLANs + #7 Offsite backup                         | Alto     |
| 5      | #8 Backup verificado + #10 Elegir torrent client     | Bajo     |
| 6      | #11-#16 Mejoras menores                              | Bajo     |
