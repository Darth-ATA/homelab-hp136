# Tasks: ha-air-quality-47 — Air Quality Notifications

## Review Workload Forecast

- **Estimated changed lines**: ~90 (`+20` configuration.yaml, `+70` automations.yaml)
- **Files touched**: 2
- **400-line budget risk**: Low (well under 100 lines)
- **Chained PRs recommended**: No
- **Decision needed before apply**: No

## Task 1: Add input_select.air_quality_state to configuration.yaml

- **ID**: TASK-001
- **Scope**: `ha-config/configuration.yaml` — add new `input_select` block
- **Description**:
  Add `input_select.air_quality_state` with options `normal` (initial) and `bad`.
  Place it right after the existing `input_select.ventilation_state` block (after line 72),
  following the same YAML structure pattern:
  - Same icon convention (`mdi:air-filter`)
  - `name` in Spanish: "Calidad del aire - Estado"
  - Two options only: `normal`, `bad`
  - Initial state: `normal`
- **Verification**:
  - After apply, HA will reload configuration → entity `input_select.air_quality_state` must appear in Developer Tools → States
  - Run `ha entity list | grep air_quality_state` or check in HA UI
  - YAML syntax must pass `ha core check` (Home Assistant config check)
- **Rollback**:
  ```
  git checkout main -- ha-config/configuration.yaml
  ```
  OR manually remove the `air_quality_state:` block from `input_select:` in configuration.yaml and reload.

## Task 2: Create air quality automation in automations.yaml

- **ID**: TASK-002
- **Scope**: `ha-config/automations.yaml` — add new automation block (append at end of file)
- **Description**:
  Add a new automation following the exact pattern of the existing ventilation automation
  (id: `1768000000001`, alias: `Ventilación: Notificaciones ventanas`, lines 525-600) but with:

  **Trigger**:
  - `trigger: state` on `sensor.meter_pro_co2_9540_dioxido_de_carbono`
  - 5-minute debounce via `for: minutes: 5` (numeric_state trigger with `for`, same pattern as
    ventilation automation lines 127-128)

  **Actions — state machine logic**:
  - Read `input_select.air_quality_state` into variable `cur`, with fallback to `normal` if unknown
  - Check sensor availability (`unavailable`, `unknown`, `none`) — same pattern as line 137
  - Compute `target`:
    - If sensor unavailable → `normal` (no change, skip notifications)
    - Else if CO₂ > 1000 AND `cur == 'normal'` → `bad`
    - Else if CO₂ < 800 AND `cur == 'bad'` → `normal`
    - Else → `cur` (no transition)
  - Only act on state change: `if target != cur`
    - `input_select.select_option` → `air_quality_state` → `target`
    - Send notification:
      - `bad` → notify "open windows" (title: "🌬️ Calidad del aire",
        message: "La concentración de CO₂ es alta. Abre las ventanas para ventilar.")
      - `normal` (recovery) → notify "air quality recovered"
        (title: "🌬️ Calidad del aire",
         message: "La calidad del aire ha mejorado. Ya puedes cerrar las ventanas.")
    - Both notifications to: `notify.mobile_app_alejandros_iphone` AND
      `notify.mobile_app_miriam_iphone` via `notify.send_message` (same pattern as lines 570-577)
    - Also create `persistent_notification.create` (same pattern as lines 578-598)

  **IDs**:
  - Automation ID: `'1768000000002'` (follows the convention from existing automations)
  - Alias: `'Calidad de aire: Notificaciones'`
  - Description: explaining the state machine purpose

  **Mode**: `single` (same as ventilation automation)

  **Messages**: In español ibérico (no voseo), using `tú` forms:

  | Scenario | Title | Message |
  |----------|-------|---------|
  | Bad air (CO₂ > 1000 for 5 min) | "🌬️ Calidad del aire" | "La concentración de CO₂ es alta. Abre las ventanas para ventilar." |
  | Recovery (CO₂ < 800 for 5 min) | "🌬️ Calidad del aire" | "La calidad del aire ha mejorado. Ya puedes cerrar las ventanas." |

  **ping_ids** (notification dedup tags):
  - Bad air: `air_quality_bad`
  - Recovery: `air_quality_normal`

- **Verification**:
  - After reload, automation `1768000000002` must appear in Developer Tools → Automations
  - Trigger verification (manual, user performs):
    1. Blow on the CO₂ sensor to raise readings above 1000 ppm and wait 5 minutes
    2. Confirm notification arrives on both phones
    3. Let CO₂ drop below 800 ppm or breathe into bag to trigger recovery
    4. Confirm recovery notification arrives on both phones
  - YAML syntax must pass HA config check
  - Check `input_select.air_quality_state` state changes correctly:
    `normal → bad → normal`
- **Rollback**:
  ```
  git checkout main -- ha-config/automations.yaml
  ```
  OR manually remove the automation block with id `1768000000002` from automations.yaml.

## Task Ordering

1. **TASK-001** MUST be applied first — `input_select.air_quality_state` must exist in HA
   before the automation references it, or the automation will log errors on load.
2. **TASK-002** MUST be applied second — references the entity created in TASK-001.

## Verification Strategy

- **Static**: Review YAML syntax for both files. Confirm entity ID consistency
  (`air_quality_state` used identically in both files). Confirm automation IDs don't collide
  with existing ones (`1768000000001` is ventilation, `1768000000002` is this one).
- **Dynamic**: After apply, user reloads HA configuration and checks:
  1. `input_select.air_quality_state` appears in entity registry
  2. Automation `1768000000002` appears in automation editor
  3. Manual test with CO₂ sensor perturbation

## Rollback Strategy

- Single `git checkout main -- ha-config/automations.yaml ha-config/configuration.yaml` reverts both files
- The `input_select.air_quality_state` entity left in HA state is harmless — it will persist with
  last known value but will never be referenced again
- No data loss risk (this is configuration only, no database state)

## Commit Strategy

### Commit 1: feat(ha-config): add air_quality_state input_select for CO₂ notifications
- Files: `ha-config/configuration.yaml`
- Adds `input_select.air_quality_state` block after ventilation_state

### Commit 2: feat(ha-config): add air quality notification automation for CO₂ sensor
- Files: `ha-config/automations.yaml`
- Adds new automation with CO₂ threshold logic and dual-phone notifications

Both commits together form the full change. They are deliberately separated because
the input_select must exist before the automation references it.
