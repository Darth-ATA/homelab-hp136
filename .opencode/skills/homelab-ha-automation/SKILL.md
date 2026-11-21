---
name: homelab-ha-automation
description: "Trigger: cambios en ha-config/ (automations.yaml, scripts.yaml, configuration.yaml) o cualquier automatización de Home Assistant. Obliga a validar en el homelab real antes de dar por hecho el cambio."
license: MIT
metadata:
  author: gentleman-programming
  version: "1.0"
---

## Activation Contract

Use esta skill cuando el trabajo toque archivos bajo `ha-config/` o cualquier automatización de Home Assistant del homelab.

## Hard Rules

- Nunca des por hecho que un cambio de automatización funciona solo porque el YAML es válido.
- Después de editar `ha-config/automations.yaml` (o `scripts.yaml` / `configuration.yaml`), ejecuta:
  1. Validación de sintaxis YAML local.
  2. Despliegue al homelab con `./scripts/deploy-ha-config.sh`.
  3. Revisión de logs de Home Assistant (`ha core logs`) para confirmar que no hay errores de automatización ni tracebacks relacionados.
  4. Si el cambio afecta a un escenario concreto (p. ej. hora barata de lavadora), verifica el estado de las entidades implicadas en Developer Tools de HA o reproduce el trigger si es seguro hacerlo.
- Si no hay acceso al homelab, detente y pregunta al usuario antes de continuar.

## Decision Gates

| Situación | Acción |
| --- | --- |
| Se edita `ha-config/automations.yaml` | Desplegar y revisar logs antes de cerrar la tarea |
| El YAML tiene error de sintaxis | Corregir localmente antes de desplegar |
| No hay acceso al homelab | Detener y preguntar al usuario |
| Hay errores en los logs de HA | No dar la tarea como terminada; corregir y re-desplegar |

## Execution Steps

1. Identificar qué archivos de `ha-config/` se van a tocar.
2. Validar YAML localmente (`python3 -c "import yaml; yaml.safe_load(open(...))"`).
3. Ejecutar `./scripts/deploy-ha-config.sh <archivo>` con el(s) archivo(s) modificado(s).
4. Revisar logs de HA: `ha core logs | grep -i <alias o id de la automatización>`.
5. Reportar al usuario qué se desplegó, si HA Core se reinició sin errores y qué se observó en los logs.

## Output Contract

- Indicar qué archivos se desplegaron.
- Indicar si HA Core se reinició sin errores.
- Indicar qué se observó en los logs (errores o limpio).
