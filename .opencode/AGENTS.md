# OpenCode Gentle AI rules — homelab-hp136

## Home Assistant homelab validation

When touching files under `ha-config/` (`automations.yaml`, `scripts.yaml`, `configuration.yaml`) or any Home Assistant automation:

- Do not take the change for granted just because the YAML is valid.
- Deploy to the homelab with `./scripts/deploy-ha-config.sh`.
- Review HA logs (`ha core logs`) to confirm there are no automation errors.
- If you don't have access to the homelab, stop and ask the user before continuing.
