# Learnings — Home Assistant Automations (Washing Machine)

## Deployment

- The script `scripts/deploy-ha-config.sh` expects **relative filenames** (`automations.yaml`), **not absolute paths**. Passing absolute paths makes `resolve_files` fail to find the files and exit with "No valid files to deploy".
- You cannot have **two `input_select:` blocks** at the same level in `configuration.yaml`. YAML merges duplicate keys and the second overwrites the first; all `input_select` entries must live in a single block.

## HACS / Marketplace

- HACS **does not work on Home Assistant 2026.11 and newer** (verified on 2026.11.2). It has been replaced by the native **Marketplace** integration.
- Community cards such as `custom:button-card` are installed via Settings → Devices & Services → Marketplace.
- Custom components like `claytonjn/hass-circadian_lighting` are available via the native Marketplace (version 2.1.7). Once installed, configure in `configuration.yaml`:
  ```yaml
  circadian_lighting:

  switch:
    - platform: circadian_lighting
      name: "Circadian Lighting - Despacho"
      lights_ct:
        - light.ventilador_de_techo_despacho_main_light
        - light.innr_rb_272_t
  ```
  The `name` and `alias` values are kept in Spanish because they appear in the HA UI for household members; repo code and docs stay in English.

## Skill `homelab-ha-automation`

This skill is mandatory when touching `ha-config/`. Its hard rules:

1. Never assume a Home Assistant automation works just because the YAML is valid.
2. After editing `automations.yaml`/`scripts.yaml`/`configuration.yaml`, run:
   1. Local YAML syntax validation.
   2. Deploy with `./scripts/deploy-ha-config.sh`.
   3. Review `ha core logs` to confirm there are no automation errors or tracebacks.
   4. Check the involved entities in Developer Tools if the change affects a concrete scenario.
3. If you don't have access to the homelab, stop and ask the user before continuing.
4. If there are errors in HA logs, do not consider the task done; fix and re-deploy.

## Washing machine state design

- Before: 5 scattered `input_boolean` helpers with confusing semantics (`lavadora_tendida=ON` meant "pending to hang").
- After: a single `input_select.lavadora_estado` with 4 explicit states (`inactivo`, `lavando`, `terminado_pendiente_tendido`, `tendido`) plus 2 internal PVPC control booleans.
- The "Ya tendí" button only works when the state is `terminado_pendiente_tendido`.
- The reset turns flags off before returning to `inactivo` to prevent the 5-minute reminder from firing again.
