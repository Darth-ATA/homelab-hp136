# PVPC (Spain Electricity Pricing) — ha-pvpc-next

Integración del precio horario de la luz en Home Assistant usando el custom component `ha-pvpc-next`.

**Por qué no la integración core**: La integración `pvpc_hourly_pricing` de HA Core se rompió el 1 de enero de 2026 (`KeyError: 2026` en la librería `aiopvpc` porque los festivos estaban hardcodeados solo hasta 2025).

**Por qué no HA-PVPC-Updated**: Ese fork tiene festivos hardcodeados hasta 2029 — mismo problema, solo postergado.

**Por qué ha-pvpc-next**: Usa [`python-holidays`](https://github.com/dr-prodigy/python-holidays), que se actualiza dinámicamente. No expira.

## Quick path (scripted)

```bash
# Desde el repo, conéctate al Proxmox host y ejecuta:
./scripts/setup-pvpc.sh
```

Esto instala el componente, el card, reinicia HA y verifica los sensores.
Deja 3 pasos manuales (ver post-setup).

Para opciones: `./scripts/setup-pvpc.sh --help`

## Instalación manual

### 1. Descargar el componente

```bash
cd /tmp
curl -sL https://github.com/privatecoder/ha-pvpc-next/archive/refs/tags/2.2.2.tar.gz | tar xz
```

### 2. Copiar a Home Assistant

```bash
# Copiar al container HA
docker cp ha-pvpc-next-2.2.2/custom_components/pvpc_next homeassistant:/config/custom_components/pvpc_next/
```

Si no tenés acceso directo a Docker, podés copiar al VM y usar `qm guest exec`:

```bash
# Desde el Proxmox host
scp -r ha-pvpc-next-2.2.2/custom_components/pvpc_next root@192.168.1.100:/tmp/
qm guest exec 100 -- sh -c 'cp -r /tmp/pvpc_next /config/custom_components/'
```

### 3. Crear config entry

El componente se configura escribiendo directamente en `.storage/core.config_entries`:

```json
{
  "data": {
    "tariff": "2.0TD",
    "power_p1": 3450,
    "power_p3": 3450
  },
  "options": {},
  "domain": "pvpc_next",
  "version": 7,
  "minor_version": 1
}
```

### 4. Reiniciar HA

```bash
docker exec homeassistant ha core restart
```

## Verificar

Después del reinicio, consultar el estado via el Unix socket del supervisor:

```bash
docker exec homeassistant sh -c \
  "curl -s --unix-socket /run/supervisor/core.sock \
    http://supervisor/api/states/sensor.esios_current_price"
```

Debería devolver algo como:

```json
{"entity_id":"sensor.esios_current_price","state":"0.13959",...}
```

## Lovelace Card — pvpc-hourly-pricing-card

Gráfico horario de precios PVPC para el dashboard:

```yaml
type: custom:pvpc-hourly-pricing-card
entity: sensor.esios_current_price
entity_period: sensor.esios_current_period
title: Precio Luz hoy
```

### Instalación

```bash
# Descargar el card (v3.0.0-next)
cd /tmp
curl -sL https://github.com/privatecoder/pvpc-hourly-pricing-card/archive/refs/heads/master.tar.gz | tar xz

# Copiar a la carpeta de community resources
docker cp pvpc-hourly-pricing-card-master/dist/pvpc-hourly-pricing-card.js \
  homeassistant:/config/www/community/pvpc-hourly-pricing-card/
```

> **HA 2026.6 (storage mode)**: Los dashboards en storage mode solo aceptan resources vía UI. Ir a *Settings → Dashboards → Resources → Add Resource* y apuntar a `/local/community/pvpc-hourly-pricing-card/pvpc-hourly-pricing-card.js`. Recargar la página.

## Sensores

23 entidades registradas:

| Sensor | Descripción | Unidad |
|--------|-------------|--------|
| `sensor.esios_current_price` | Precio actual | €/kWh |
| `sensor.esios_avg_price_today` | Precio medio hoy | €/kWh |
| `sensor.esios_min_price` | Precio mínimo hoy | €/kWh |
| `sensor.esios_max_price` | Precio máximo hoy | €/kWh |
| `sensor.esios_next_price` | Siguiente precio programado | €/kWh |
| `sensor.esios_next_price_in` | Tiempo hasta siguiente precio | minutos |
| `sensor.esios_next_price_level` | Nivel siguiente precio | — |
| `sensor.esios_next_best_price` | Mejor precio próximo | €/kWh |
| `sensor.esios_next_best_in` | Tiempo hasta mejor precio | minutos |
| `sensor.esios_next_best_level` | Nivel mejor precio próximo | — |
| `sensor.esios_better_prices_ahead` | ¿Hay mejores precios después? | bool |
| `sensor.esios_next_period` | Siguiente período tarifario (P1/P2/P3) | — |
| `sensor.esios_next_period_in` | Tiempo hasta siguiente período | horas |
| `sensor.esios_current_period` | Período actual (P1/P2/P3) | — |
| `sensor.esios_current_power_period` | Período de potencia actual (P1/P2/P3) | — |
| `sensor.esios_next_power_period` | Siguiente período de potencia | — |
| `sensor.esios_next_power_period_in` | Tiempo hasta cambio de potencia | horas |
| `sensor.esios_available_power` | Potencia contratada disponible | W |
| `sensor.esios_current_price_level` | Nivel de precio actual | — |
| `sensor.esios_tariff` | Tarifa configurada | — |
| `sensor.esios_pvpc_data_id` | Internal data ID | — |
| `sensor.esios_price_mode` | Modo de precio (pvpc/indexed) | — |
| `sensor.esios_api_source` | Fuente API (public/private) | — |

## Supervisor API Sockets

El container HA expone un Unix socket del supervisor que permite consultar el estado de entidades **sin autenticación**:

```bash
# Listar entidad específica
docker exec homeassistant sh -c \
  "curl -s --unix-socket /run/supervisor/core.sock \
    http://supervisor/api/states/sensor.esios_current_price"

# Listar TODAS las entidades
docker exec homeassistant sh -c \
  "curl -s --unix-socket /run/supervisor/core.sock \
    http://supervisor/api/states" | python3 -m json.tool | head -100
```

La variable `SUPERVISOR_TOKEN` existe en el entorno del container pero **no funciona** como Bearer token contra `http://supervisor/` (siempre 401). El socket `core.sock` sí funciona sin token.

## API Key

La API pública de ESIOS funciona **sin token** para la tarifa 2.0TD. Solo se necesita token de REE para:

- Precios de inyección (vertido a red)
- PVPC indexada

## Troubleshooting

### No aparecen sensores después del reinicio

Revisar logs del container:

```bash
docker logs homeassistant 2>&1 | grep -i pvpc
```

### Los sensores aparecen como `unavailable`

El coordinator no pudo conectar con la API de ESIOS. Verificar conectividad desde el container:

```bash
docker exec homeassistant sh -c \
  "curl -sI https://api.esios.ree.es/archives/ | head -5"
```

### Forzar refresh del coordinator

Si los sensores existen pero están sin datos, forzar una actualización desde el container:

```bash
docker exec homeassistant sh -c \
  "curl -s -X POST \
    --unix-socket /run/supervisor/core.sock \
    http://supervisor/api/services/pvpc_next/update"
```

Esto llama al servicio `pvpc_next.update` que fuerza al coordinator a refrescar los datos de ESIOS inmediatamente.

### docker cp falla

`docker cp` solo funciona con destinos dentro de `/config/`. No usar `/tmp/` como destino intermedio dentro del container. Usar `--pass-stdin` con `qm guest exec` para pipear scripts:

```bash
cat /tmp/script.py | ssh proxmox-host "qm guest exec 100 --pass-stdin -- sh -c 'docker exec -i homeassistant sh -c \"cat > /tmp/script.py && python3 /tmp/script.py\"'"
```

## Post-Setup (manual)

Estos pasos solo pueden hacerse desde la UI de HA porque el storage mode de HA 2026.6 ignora configuraciones por YAML/JSON:

1. **Crear config entry**: *Settings → Devices & Services → Add Integration → PVPC Next*. Configurar tarifa `2.0TD`, potencia `3450W`.
2. **Registrar resource del card**: *Settings → Dashboards → Resources → Add Resource*. URL: `/local/community/pvpc-hourly-pricing-card/pvpc-hourly-pricing-card.js`.
3. **Agregar card al dashboard**: Editar dashboard → *Add Card → Custom: PVPC Hourly Pricing*.

## Referencias

- [ha-pvpc-next en GitHub](https://github.com/privatecoder/ha-pvpc-next)
- [API pública ESIOS](https://api.esios.ree.es)
- Issue original: [#51](https://github.com/Darth-ATA/homelab-hp136/issues/51)
