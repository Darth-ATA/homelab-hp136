# Tasks: ha-fan-48 — Study ceiling fan with real temperature sensors

## Review Workload Forecast

- **Estimated changed lines**: ~180 (73 deleted + 85 modified + 95 new + 8 new configuration)
- **Files affected**: 2 (ha-config/automations.yaml, ha-config/configuration.yaml)
- **PR recommendation**: Single PR — well under 400-line budget
- **Risk**: Low — no structural changes, pure YAML automation logic

## Dependency Graph

```
T1 (input_select) ──→ T3 (ventilation notifications)
T2 (fan control)   (independent)
```

## Tasks

### T1: [x] Add `input_select.ventilation_state` to configuration.yaml

**Summary**: Define the state machine entity for ventilation notification dedup.

**Files**: `ha-config/configuration.yaml`

**Key changes**:
- [x] Added `input_select.ventilation_state` block alongside existing `input_boolean` definitions
- [x] Options: `normal`, `ventilation_recommended`, `close_windows`
- [x] Initial: `normal`
- [x] Icon: `mdi:window-open-variant`

**Preconditions**: None

**Verification**: After HA config reload, check Developer Tools → States for `input_select.ventilation_state` with initial value `normal`.

---

### T2: [x] Replace fan automation with temperature-based speed control

**Summary**: Replace automation ID `1749052800002` (Circadiana: Ventilador despacho) with new temperature-based fan control automation.

**Files**: `ha-config/automations.yaml`

**Key changes**:
- [x] Replaced automation `1749052800002` (old solar-elevation logic) with new temperature-based automation
- [x] New ID: `1768000000000`
- [x] Alias: `Circadiana: Ventilador despacho (temp)`
- [x] Triggers: time_pattern /15 + state on `sensor.switchbot_indoor_temperature` with for: 5 min
- [x] Condition: fan is ON (guard)
- [x] Actions (choose chain, first match wins):
  1. Sensor unavailable/unknown → system_log.write (no-op)
  2. T < 24°C → `fan.turn_off`
  3. Quiet hours [23:00, 08:00) → `fan.set_percentage: 25`
  4. T ≥ 30°C → 100%
  5. 28 ≤ T < 30°C → 75%
  6. 26 ≤ T < 28°C → 50%
  7. 24 ≤ T < 26°C → 25%
- [x] Mode: single

**Preconditions**: None (independent of T1/T3)

**Verification**:
- [x] Developer Tools: mock sensor values for each band and verify speed
- [x] Test at 23:00 with T=30°C → verify 25%
- [x] Test at 08:00 with T=30°C → verify 100%
- [x] Test with fan OFF → verify no action

---

### T3: [x] Add ventilation notification automation

**Summary**: New automation that monitors indoor vs outdoor temperature and sends notifications to open/close windows based on a state machine.

**Files**: `ha-config/automations.yaml` (appended)

**Key changes**:
- [x] New automation with ID `1768000000001`
- [x] Alias: `Ventilación: Notificaciones ventanas`
- [x] Triggers: state change on either `sensor.switchbot_indoor_temperature` or `sensor.switchbot_outdoor_temperature`
- [x] Actions: template-based state machine (from design.md)
  - [x] Computes current state with graceful degradation for unavailable input_select
  - [x] Validates both sensors (unavailable/unknown/none → treated as unavailable)
  - [x] Computes target state with hysteresis (±1.0°C delta)
  - [x] On transition: updates `input_select.ventilation_state`, sends notification + persistent_notification
- [x] Notifications (Spanish from Spain):
  - `ventilation_recommended`: "Abre las ventanas — está más fresco fuera que dentro."
  - `close_windows`: "Cierra las ventanas — está más caliente fuera que dentro."
  - `normal`: no notification
- [x] Notify target: `notify.alejandros_iphone` + `persistent_notification.create`
- [x] Mode: single

**Preconditions**: T1 (input_select entity must exist)

**Verification**:
- Set indoor=26°C, outdoor=25°C → verify state = `ventilation_recommended` + notification
- Set indoor=24°C, outdoor=25°C → verify state = `close_windows` + notification
- Re-trigger same condition → verify no duplicate notification
- Set both sensors to `unavailable` → verify state = `normal`, no notification
