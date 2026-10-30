# Spec: ha-fan-48 — Study ceiling fan with real temperature sensors

## Overview

Replace the solar-elevation proxy logic in automation `1749052800002` with actual Switchbot temperature readings. Add cross-ventilation notifications via a state machine.

This spec covers two capabilities: **fan-study-temperature-control** and **ventilation-notifications**.

## Dependency: `input_select.ventilation_state`

Before any ventilation notification automation can run, the following entity MUST exist in Home Assistant:

**Entity ID**: `input_select.ventilation_state`
**Options**: `normal`, `ventilation_recommended`, `close_windows`
**Initial state**: `normal`

This entity serves as a dedup state machine — notifications fire only on transition, not on every sensor update.

**Definition location**: The implementation MUST create this entity either in `ha-config/configuration.yaml` (consistent with existing `input_boolean` definitions) or via the HA UI helpers. The spec requires it exists; the design decides where.

---

## Capability 1: `fan-study-temperature-control`

Replace the time-of-day + solar-elevation fan speed logic with temperature-based speed bands.

### Requirements

| ID | Requirement | Testability |
|----|-------------|-------------|
| R1.1 | The automation MUST set fan speed according to the indoor temperature band table below, but ONLY when the fan entity `fan.ventilador_de_techo_despacho_main_fan` is already ON. | Can verify by running `fan.turn_on` then invoking automation |
| R1.2 | The automation MUST NEVER turn the fan ON. If the fan is OFF, no action is taken regardless of temperature. | Can verify by running `fan.turn_off` then invoking automation — speed must not change |
| R1.3 | Temperature-to-speed bands (inclusive lower bound, exclusive upper bound, sensor unit = °C): | |
| | `T < 24` → turn fan OFF via `fan.turn_off` | Verify each band boundary in Developer Tools |
| | `24 ≤ T < 26` → `fan.set_percentage` at 25% | |
| | `26 ≤ T < 28` → `fan.set_percentage` at 50% | |
| | `28 ≤ T < 30` → `fan.set_percentage` at 75% | |
| | `T ≥ 30` → `fan.set_percentage` at 100% | |
| R1.4 | During quiet hours (23:00 inclusive to 08:00 exclusive), the fan speed MUST be capped at 25% regardless of temperature. If the temperature band would set a lower speed (or OFF), that lower value takes precedence. | Verify at 07:59 with T=30°C (expect 25%); verify at 08:00 with T=30°C (expect 100%) |
| R1.5 | If the indoor temperature sensor (`sensor.switchbot_indoor_temperature`) state is `unavailable` or `unknown`, the automation MUST NOT change fan speed. The current speed is preserved. | Simulate sensor unavailable, invoke automation, verify speed unchanged |
| R1.6 | The automation must re-evaluate when either the indoor temperature changes OR the clock crosses a quiet-hours boundary. The re-evaluation must include a debounce period of at least 5 minutes to prevent rapid fluctuation. | Change temperature and immediately invoke — verify no change before 5 min; wait 5 min and verify |
| R1.7 | When the indoor temperature drops below 24°C and the fan is ON, the automation MUST turn the fan OFF via `fan.turn_off`. This is the only `fan.turn_off` action in this capability. | Set T=23.9°C with fan on at 50% → verify fan turns off |
| R1.8 | When `fan.turn_off` is issued (R1.7), the automation MUST NOT interfere with upcoming future temperature rises — the user must manually turn the fan back ON for the automation to resume. | After fan turns off via R1.7, raise T to 27°C → verify fan stays OFF |

### Acceptance Criteria

| ID | Criterion | Verification method |
|----|-----------|---------------------|
| AC1.1 | All 5 temperature bands produce the correct speed ±1°C at the boundary | Developer Tools: `homeassistant.update_entity` with mocked sensor values |
| AC1.2 | Fan speed never exceeds 25% between 23:00:00 and 07:59:59 | Test at 03:00 with T=35°C setpoint → verify speed = 25% |
| AC1.3 | Fan speed follows temperature bands normally from 08:00:00 onward | Test at 08:00 with T=30°C → verify speed = 100% |
| AC1.4 | Fan is NEVER turned on by this automation | Automation trigger with fan OFF + any temperature → verify no action |
| AC1.5 | Unavailable sensor preserves current speed | Simulate `sensor.switchbot_indoor_temperature` = `unavailable` → verify speed unchanged |
| AC1.6 | T < 24°C while fan is ON → fan turns OFF | Set T=23°C, fan ON at 50% → verify fan OFF after automation runs |

### Scenarios

#### Normal operation

1. **Daytime cooling**: T=27°C at 14:00, fan ON → speed set to 50%. Temperature drops to 25°C → speed set to 25%.
2. **Hot afternoon**: T=32°C at 16:00, fan ON → speed set to 100%.
3. **Cool evening**: T=22°C at 20:00, fan ON → fan turns OFF.
4. **User override**: User manually sets fan to 30% at 14:00 with T=29°C. Next automation run → speed set to 75% (overrides manual).
5. **Morning ramp-up**: User turns fan ON at 09:00 with T=25°C → speed set to 25%.

#### Edge cases

1. **Quiet hours boundary at 23:00:00**: T=28°C, fan ON at 50%. Clock hits 23:00 → quiet hours begin → speed drops to 25%.
2. **Quiet hours boundary at 08:00:00**: T=28°C, fan ON at 25%. Clock hits 08:00 → quiet hours end → speed rises to 50%.
3. **Boundary at 24°C exactly**: T=24.0°C → speed = 25%. T=23.9°C → fan turns OFF.
4. **Boundary at 30°C exactly**: T=30.0°C → speed = 100%.
5. **Sensor reports valid but stale**: Sensor last updated 30 minutes ago but state is `25`. Automation uses this value as-is (no staleness check required).

#### Failure modes

1. **Sensor unavailable**: `sensor.switchbot_indoor_temperature` state = `unavailable` → no speed change.
2. **Sensor unknown**: State = `unknown` (sensor not yet initialized) → no speed change.
3. **Fan entity unavailable**: Fan entity itself is unavailable → automation trigger's guard condition fails, no action taken. (Graceful — no special handling needed beyond the existing ON guard.)
4. **Simultaneous quiet hours + <24°C**: T=22°C at 02:00, fan ON at 25% from a previous manual set. The <24°C rule says turn OFF, which takes precedence over the quiet hours 25% cap. → fan turns OFF. (R1.4: lowest value takes precedence.)

### Non-requirements

- **No auto-turn-on**: Explicitly NOT required. The fan must be manually turned ON.
- **No presence detection**: No occupancy sensor is involved. If nobody is in the room, the automation still runs based on temperature.
- **No outdoor temperature in speed logic**: Only indoor temperature drives fan speed. Outdoor temperature is used ONLY in the ventilation-notifications capability.
- **No ceiling fan direction control**: Changing the fan's rotation direction (summer/winter mode) is NOT in scope.
- **No staleness heuristic**: The spec does not require checking `last_updated` or `last_changed` timestamps on the sensor. A valid but old reading is still acted upon.
- **No graceful degradation on sensor recovery**: When a sensor recovers from unavailable, the automation picks it up on the next trigger cycle naturally — no special recovery logic.

---

## Capability 2: `ventilation-notifications`

Compare indoor vs. outdoor temperature and notify the user to open or close windows based on the temperature delta. Uses a state machine to prevent duplicate notifications.

### Requirements

| ID | Requirement | Testability |
|----|-------------|-------------|
| R2.1 | The automation MUST compare `sensor.switchbot_indoor_temperature` and `sensor.switchbot_outdoor_temperature` to decide ventilation state. | Verify comparison logic via Developer Tools |
| R2.2 | The system MUST maintain a ventilation state via `input_select.ventilation_state` with exactly 3 states: `normal`, `ventilation_recommended`, `close_windows`. | Read entity state via Developer Tools |
| R2.3 | State transitions MUST follow this table: | Verify each transition by manipulating sensor values |
| | **From** → **To** | **Condition** |
| | `normal` → `ventilation_recommended` | outdoor_temp ≤ (indoor_temp - 1.0°C) |
| | `ventilation_recommended` → `close_windows` | outdoor_temp ≥ (indoor_temp + 1.0°C) |
| | `close_windows` → `ventilation_recommended` | outdoor_temp ≤ (indoor_temp - 1.0°C) |
| | `close_windows` → `normal` | Both sensors unavailable |
| | `ventilation_recommended` → `normal` | Both sensors unavailable |
| R2.4 | When the state transitions TO `ventilation_recommended`, the automation MUST send a notification: "Abre las ventanas — está más fresco fuera que dentro." | Verify notification content on transition |
| R2.5 | When the state transitions TO `close_windows`, the automation MUST send a notification: "Cierra las ventanas — está más caliente fuera que dentro." | Verify notification content on transition |
| R2.6 | When the state transitions TO `normal` (sensor recovery fallback), the automation MUST NOT send a notification. | Simulate both sensors unavailable from any state → verify no notification |
| R2.7 | Notifications MUST use the `notify.alejandros_iphone` mobile app integration (or equivalent mobile_app notification target for Alejandro). | Check automation YAML for correct service |
| R2.8 | A notification MUST be sent ONLY when the `input_select.ventilation_state` transitions. Re-entering the same state MUST NOT send a notification. | Set state to `ventilation_recommended`, trigger again with same condition → verify no duplicate notification |
| R2.9 | If either sensor is unavailable, the ventilation state MUST NOT transition to `ventilation_recommended` or `close_windows` (sensor guard). The only allowed transition when sensors are unavailable is to `normal`. | With state = `close_windows` and both sensors unavailable → verify transition to `normal` |
| R2.10 | If both sensors are available but one returns a non-numeric state (e.g., `unknown`), it MUST be treated as unavailable for the purposes of R2.9. | Set indoor to `unknown`, outdoor to `25.0` → verify no ventilation transition |

### Acceptance Criteria

| ID | Criterion | Verification method |
|----|-----------|---------------------|
| AC2.1 | `normal` → `ventilation_recommended` fires when outdoor ≤ indoor - 1.0°C | Set indoor=26.0, outdoor=25.0 → verify state = ventilation_recommended + notification |
| AC2.2 | `ventilation_recommended` → `close_windows` fires when outdoor ≥ indoor + 1.0°C | Set indoor=24.0, outdoor=25.0 → verify state = close_windows + notification |
| AC2.3 | `close_windows` → `ventilation_recommended` fires when outdoor ≤ indoor - 1.0°C | Set indoor=26.0, outdoor=25.0 → verify state = ventilation_recommended + notification |
| AC2.4 | Both sensor failure from any non-normal state → transition to `normal`, NO notification | Set both sensors to `unavailable` from `ventilation_recommended` → verify state = normal, no notification |
| AC2.5 | Same-state trigger produces NO notification | Manually set state to `ventilation_recommended`, re-trigger with same delta → verify no notification in logbook |
| AC2.6 | Persistent notification is also created alongside mobile notification | Check `persistent_notification` list in Developer Tools after transition |

### Scenarios

#### Normal operation

1. **Evening cooling**: Indoor=26°C, Outdoor=22°C (delta = -4°C). State = ventilation_recommended. Notification: "Hacé corrientes…" User opens windows.
2. **Morning heat-up**: Indoor=24°C, Outdoor=28°C (delta = +4°C). State = close_windows. Notification: "Está entrando calor…" User closes windows.
3. **Sensor recovery**: State = close_windows. Both sensors die (unavailable). State → normal. No notification. Sensors come back: state stays normal until conditions are met again.

#### Edge cases

1. **Delta exactly at threshold**: indoor=25.0, outdoor=24.0 → exactly -1.0°C. Condition is `≤`, so this TRIGGERS ventilation_recommended. (Boundary: ≤ is inclusive; a delta of exactly -1.0°C counts.)
2. **Delta at 0.9°C**: indoor=25.0, outdoor=24.1 → delta = -0.9°C. Below threshold → no transition. This provides natural hysteresis: after transitioning to ventilation_recommended at -1.0°C, the temperature must swing to +1.0°C (not just 0°C) to get back to close_windows.
3. **Rapid oscillation**: Indoor fluctuates 25.0→25.5→25.0→25.5 while outdoor is steady at 24.0. Delta oscillates around -1.0°C. The state machine (±1.0°C hysteresis) prevents repeated transitions.
4. **Sensor reports NaN or None**: State is not numeric → treat as unavailable.

#### Failure modes

1. **Indoor sensor unavailable, outdoor OK**: No ventilation transition possible (indoor data required).
2. **Outdoor sensor unavailable, indoor OK**: No ventilation transition possible (can't compare).
3. **Both sensors unavailable from `close_windows`**: State resets to `normal`. No notification.
4. **Both sensors unavailable from `ventilation_recommended`**: State resets to `normal`. No notification.
5. **Both sensors unavailable from `normal`**: State stays `normal`. No action needed.
6. **Notification service fails**: If `notify.alejandros_iphone` is unavailable, the automation should log a warning but MUST still update the `input_select.ventilation_state`. The state machine integrity is more important than the notification delivery.
7. **`input_select.ventilation_state` entity deleted or unavailable**: Automation should handle gracefully — if entity state is `unavailable` or `unknown`, default to `normal` for comparison purposes. (Design decision.)

### Non-requirements

- **No auto-ventilation**: The system does NOT open or close windows automatically. It only notifies.
- **No humidity or CO2**: Ventilation recommendation is based solely on temperature delta. Humidity, CO2, and air quality are NOT considered.
- **No schedule**: Notifications can fire at any time of day (no quiet hours). The user manages do-not-disturb on their phone.
- **No normal → normal on delta resolution**: If the temperature delta resolves (indoor ≈ outdoor) while in `ventilation_recommended`, the state does NOT go back to `normal` automatically. It stays in `ventilation_recommended` until the delta crosses the +1.0°C threshold (→ `close_windows`) or sensors fail (→ `normal`). This is intentional: the user already opened windows; no need to tell them to close unless it gets hotter outside.
- **No "close_windows" → "normal" on delta resolution**: Same reasoning — once the user closes windows based on the notification, the state machine needs a clear signal (sensor failure) to reset to normal. This prevents cycling.
- **No bilingual option**: Notifications are in Spanish from Spain (castellano), matching the user's preference. Examples: "Hace más calor fuera que dentro" (not "afuera" / "adentro" / "hacé").
- **No action buttons on notifications**: Unlike the lavadora notification (which has "Ya tendí" / "No" actions), ventilation notifications are informational only. No interactive buttons required.

---

## Implementation Scope Summary

### Files to modify

| File | Change |
|------|--------|
| `ha-config/automations.yaml` | Replace automation ID `1749052800002` (Circadiana: Ventilador despacho) with new temperature-based fan logic |
| `ha-config/automations.yaml` | Add new automation for ventilation-notifications state machine |
| `ha-config/configuration.yaml` | Add `input_select.ventilation_state` definition (or document creation via UI) |

### Entities consumed (read)

| Entity | Purpose |
|--------|---------|
| `fan.ventilador_de_techo_despacho_main_fan` | Fan to control and guard condition |
| `sensor.switchbot_indoor_temperature` | Indoor temperature for speed and ventilation |
| `sensor.switchbot_outdoor_temperature` | Outdoor temperature for ventilation comparison |
| `input_select.ventilation_state` | State machine for notification dedup |

### Entities produced (write)

| Entity | Purpose |
|--------|---------|
| `fan.ventilador_de_techo_despacho_main_fan` | `fan.set_percentage`, `fan.turn_off` |
| `input_select.ventilation_state` | `input_select.select_option` to set state |
| `notify.alejandros_iphone` | Send ventilation notifications |

---

## Validation Notes

1. **Quiet hours are device time**: The automation uses HA's internal clock time. If the HA system timezone is Buenos Aires (UTC-3), quiet hours operate in that timezone.
2. **Sensor precision**: Switchbot sensors typically report with 0.1°C precision. The temperature bands handle this fine.
3. **Fan percentage mapping**: The `ble_adv` integration exposes the fan as a standard `fan` entity with `percentage` 0-100. The speeds map as: `percentage=25` = low, `percentage=50` = medium, `percentage=75` = medium-high, `percentage=100` = high. This is the existing behavior from the current automation and must be preserved.
