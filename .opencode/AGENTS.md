# Reglas de OpenCode Gentle AI — homelab-hp136

## Validación en homelab (Home Assistant)

Cuando se toquen archivos bajo `ha-config/` (`automations.yaml`, `scripts.yaml`, `configuration.yaml`) o cualquier automatización de Home Assistant:

- No des el cambio por hecho solo porque el YAML sea válido.
- Despliega al homelab con `./scripts/deploy-ha-config.sh`.
- Revisa los logs de HA (`ha core logs`) para confirmar que no hay errores de automatización.
- Si no hay acceso al homelab, detente y pregunta al usuario antes de continuar.
