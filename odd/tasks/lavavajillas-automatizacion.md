# Lavavajillas — Automatización inteligente por PVPC

- **Objetivo:** Replicar la automatización de lavadora para el lavavajillas Laurus LSV60-4 conectado al enchufe Sonoff S60ZBTPF (antes termo eléctrico).
- **Branch:** main (trabajo directo, sin rama de feature)
- **Estrategia de entrega:** ask-on-risk (default)
- **Runner de tests:** validación YAML local + `./scripts/deploy-ha-config.sh` + revisión de `ha core logs`

## Specs

S1: Detectar inicio de ciclo del lavavajillas por consumo > 5W sostenido 30s en `sensor.sonoff_s60zbtpf_potencia`. Si no es hora barata dentro 08-22, gestionar espera o arranque diferido igual que la lavadora.
S2: Encender el enchufe `switch.sonoff_s60zbtpf` automáticamente cuando llegue la hora más barata (entre 08-22) si el lavavajillas fue apagado por la automatización.
S3: Encender mañana en la hora más barata si el ciclo se arrancó fuera de 08-22 y el modo diferido está activo.
S4: Detectar fin de ciclo cuando consumo < 10W durante 5 minutos y notificar al móvil para abrir el lavavajillas.
S5: Botón de acción en notificación "Ya lo abrí" que marca el lavavajillas como abierto.
S6: Reset completo al marcar "Ya lo abrí", volviendo a estado inactivo.
S7: Recordatorio cada 5 minutos si el ciclo terminó y nadie marcó "Ya lo abrí".

## Tasks

T1: Agregar helpers de configuración (template sensors, input_boolean, input_select) para lavavajillas — configuration.yaml — inline — completado
T2: Agregar automatizaciones de inicio, hora barata, fin de ciclo, acción abrir, reset y recordatorio — automations.yaml — inline — completado
T3: Validar sintaxis YAML de ambos archivos — inline — completado (ruby YAML load OK)
T4: Desplegar con `./scripts/deploy-ha-config.sh` y revisar `ha core logs` — usuario — completado (deploy OK, pendiente revisión de logs por el usuario)

## Log

L1: Usuario movió el enchufe Sonoff S60ZBTPF del termo eléctrico al lavavajillas Laurus LSV60-4 y solicita automatización parecida a la lavadora, con avisos y notificación al terminar para abrir el lavavajillas.
