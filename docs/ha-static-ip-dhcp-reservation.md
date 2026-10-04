# HA Static IP via DHCP Reservation (Router)

## Problema
HA OS tiene filesystem read-only (`/etc` es erofs). La IP estática configurada via `ip addr add` o NetworkManager **no persiste tras reboot**.

## Solución: DHCP Reservation en Router (EX520v)

### 1. Configurar Reserva DHCP en Router
```
Router UI → DHCP Server → Static Leases / Address Reservation
MAC Address: 02:8d:ab:80:c0:9d
IP Address: 10.10.10.100
```

### 2. Cambiar HA a DHCP
**Opción A - Via UI (recomendado):**
```
Settings → System → Network → Configure network interfaces
Interface: enp6s18
Method: Automatic (DHCP)
Apply → Restart Home Assistant
```

**Opción B - Via configuration.yaml:**
```yaml
# En /mnt/data/supervisor/homeassistant/configuration.yaml
# ANTES de default_config:
network:
  config:
    - interface: enp6s18
      type: ethernet
      method: auto
```
*Luego: Settings → System → Restart Home Assistant*

### 3. Verificar
```bash
# En Proxmox host
qm guest exec 100 -- ip addr show enp6s18
# Debe mostrar: 10.10.10.100/24 (asignado por DHCP)
```

### Ventajas
- ✅ Persiste tras reboot automáticamente
- ✅ No toca HA OS read-only
- ✅ Router es autoridad DHCP (única fuente de verdad)
- ✅ Config centralizada en router
- ✅ La conexión NetworkManager ya existe en overlay (`/etc/NetworkManager/system-connections/`) - solo cambiar `method: auto`

### Rollback
Si algo falla, en Proxmox console:
```bash
qm guest exec 100 -- ip link set enp6s18 up && sleep 3 && ip addr add 10.10.10.100/24 dev enp6s18 && ip route add default via 10.10.10.1 dev enp6s18
```

---

**MAC de HA:** `02:8d:ab:80:c0:9d`  
**IP reservada:** `10.10.10.100`  
**Gateway:** `10.10.10.1`  
**DNS:** `10.10.10.2` (AdGuard)
