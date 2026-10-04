# HA Static IP in 10.10.10.x Subnet

## Estado Actual
**IP Estática Manual** en `10.10.10.100` - FUNCIONA

## Problemas con DHCP Reservation
1. Router EX520v no honra la reserva estática (asigna IP del pool 10.10.10.157)
2. `dhclient` no persiste en HA OS (filesystem read-only, no `/var/lib/dhcp`, no `/etc/resolv.conf` writable)
3. NetworkManager tiene `enp6s18` como `unmanaged` (configurado por supervisor)

## Solución: IP Estática Manual

### Estado Actual ✅
- IP: `10.10.10.100/24`
- Gateway: `10.10.10.1`
- DNS: `10.10.10.2` (AdGuard)
- HA accesible en `https://ha.hp136.duckdns.org` (200 OK)

### Tras Reboot de HA (ejecutar en Proxmox Host)
```bash
qm guest exec 100 -- bash -c 'ip link set enp6s18 up && sleep 3 && ip addr add 10.10.10.100/24 dev enp6s18 2>/dev/null && ip route add default via 10.10.10.1 dev enp6s18'
```

### Verificar
```bash
qm guest exec 100 -- ip addr show enp6s18
# Debe mostrar: inet 10.10.10.100/24 scope global enp6s18

curl -s -o /dev/null -w "%{http_code}" https://ha.hp136.duckdns.org
# Debe responder: 200
```

## Configuración de Red en HA (NetworkManager)
La conexión existe en overlay persistente:
```
/mnt/data/supervisor/overlay/etc/NetworkManager/system-connections/Supervisor enp6s18.nmconnection
```
- `method: manual`
- `address1: 10.10.10.100/24,10.10.10.1`
- `dns: 10.10.10.2`
- `autoconnect: yes`

**Nota:** NetworkManager tiene la interfaz como `unmanaged` (configurado por supervisor HA OS), por eso la IP no se levanta sola tras reboot.

## Alternativas Evaluadas y Descarte
| Opción | Resultado |
|--------|-----------|
| DHCP Reservation en Router | ❌ Router no honra reserva (da IP pool) |
| dhclient en boot | ❌ Read-only FS, no persiste leases/resolv.conf |
| systemd service en overlay | ❌ Overlay no cubre /etc/systemd/system/ |
| NetworkManager managed | ❌ Supervisor fuerza unmanaged |
| Custom HA OS Build | ✅ Funcionaría pero overkill |

## Conclusión
**IP estática manual + comando post-reboot documentado** es la solución pragmática. Los reboots de HA OS son infrecuentes (solo updates de HA OS), y el comando toma ~5 segundos.

---

**MAC de HA:** `02:8d:ab:80:c0:9d`  
**IP:** `10.10.10.100`  
**Gateway:** `10.10.10.1`  
**DNS:** `10.10.10.2`
