# Design: ha-fan-48 — Study ceiling fan with real temperature sensors

## Technical Approach

Replace solar-elevation proxy in automation `1749052800002` with Switchbot temperature-based fan speed. Add separate ventilation-notifications automation with `input_select.ventilation_state` state machine for dedup. Both in `automations.yaml`; `input_select` defined in `configuration.yaml`.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  automations.yaml                            │
│                                                             │
│  ┌──────────────────────────────────────┐  ┌──────────────┐ │
│  │ fan-study-temperature-control        │  │ ventilation-  │ │
│  │                                      │  │ notifications │ │
│  │ Trigger: time_pattern /15            │  │               │ │
│  │        + state (indoor, for:5min)    │  │ Trigger:      │ │
│  │ Guard:  fan is ON                    │  │  state change │ │
│  │ Action: choose temp bands,           │  │  either sensor│ │
│  │         quiet hours cap at 25%       │  │               │ │
│  └──────────┬───────────────────────────┘  │ Action:      │ │
│             │ writes fan.%                │  │  compare temps│ │
│             │ sets input_select state     │  │  transition   │ │
│             │ (no write)                  │  │  state machine│ │
│             │                              │  │  notify on   │ │
│             │                              │  │  transition  │ │
│             │                              └──────┬──────────┘ │
└─────────────┼──────────────────────────────────────┼───────────┘
              │                                      │
              │ fan.set_percentage / fan.turn_off     │ notify.alejandros_iphone
              │ fan.ventilador_de_techo_despacho_     │
              │ main_fan                              │
              ▼                                      ▼
```

## Architecture Decisions

### Decision: Fan control trigger — dual trigger

**Choice**: `time_pattern: /15` (existing) + `state` on `sensor.switchbot_indoor_temperature` with `for: 00:05:00`.
**Alternatives**: `time_pattern: /5` alone (less responsive); state trigger alone (misses quiet hours boundary).
**Rationale**: time_pattern catches quiet hours boundaries within 15 min. State trigger with 5-min debounce reacts to sustained temp changes faster (R1.6). Lockstep with existing Circadiana cadence (circadiana: luz also runs /15).

### Decision: input_select definition — configuration.yaml

**Choice**: Define `input_select.ventilation_state` in `configuration.yaml`.
**Alternatives**: HA UI helpers (not in version control); separate YAML file (over-engineering).
**Rationale**: Follows existing pattern — `input_boolean` helpers for lavadora are in `configuration.yaml`. Keeps state machine definition in version control with automations.

### Decision: Ventilation debounce — state machine hysteresis only

**Choice**: No `for:` on state triggers; rely on ±1°C hysteresis + state machine dedup.
**Alternatives**: Add `for: 00:01:00` on sensor state triggers.
**Rationale**: Switchbot sensors report every ~3 min. The ±1°C hysteresis (R2.3) prevents rapid cycling around threshold. State-transition-only notifications (R2.8) eliminate duplicates regardless of trigger frequency. Adding `for:` would only add unnecessary latency.

## Automation 1: fan-study-temperature-control

### Trigger
```yaml
triggers:
  - trigger: time_pattern
    minutes: /15
  - trigger: state
    entity_id: sensor.switchbot_indoor_temperature
    for:
      minutes: 5
```

### Condition (guard)
```yaml
conditions:
  - condition: state
    entity_id: fan.ventilador_de_techo_despacho_main_fan
    state: 'on'
```

### Actions (choose chain — first match wins)

Priority order:
1. **Sensor unavailable/unknown** → log warning, do nothing
2. **T < 24°C** → `fan.turn_off` (always, even during quiet hours — R1.4 lowest value rule)
3. **Quiet hours [23:00, 08:00)** AND T ≥ 24°C → `fan.set_percentage: 25`
4. **T ≥ 30°C** → `fan.set_percentage: 100`
5. **28 ≤ T < 30°C** → `fan.set_percentage: 75`
6. **26 ≤ T < 28°C** → `fan.set_percentage: 50`
7. **24 ≤ T < 26°C** → `fan.set_percentage: 25`

Quiet hours condition: `after: '23:00:00', before: '08:00:00'` — HA interprets `after > before` as midnight-crossing range.

### Temperature band boundary mapping

| Spec band | YAML condition | Matches |
|-----------|---------------|---------|
| T < 24 | `numeric_state below: 24` | strictly < 24 |
| 24 ≤ T < 26 | `above: 23, below: 26` | 24-25.9 (after <24 eliminated) |
| 26 ≤ T < 28 | `above: 25, below: 28` | 26-27.9 |
| 28 ≤ T < 30 | `above: 27, below: 30` | 28-29.9 |
| T ≥ 30 | `above: 29` | 30+ (strictly > 29) |

The `above`/`below` use strict inequality, but the choose ordering ensures correct banding. T < 24 (first check) eliminates the overlap between `above: 23` and `below: 24`. The 0.1°C resolution of Switchbot sensors prevents boundary ambiguities (e.g., T=24.0000... exactly is representable as `24.0` state string).

## Automation 2: ventilation-notifications

### State machine

```
                        ┌──────────────────┐
                        │                  │
                   ┌───▶│     normal       │◀──────────────┐
                   │    │                  │                │
                   │    └────────┬─────────┘                │
                   │             │                          │
                   │    outdoor ≤ indoor - 1.0°C            │
                   │             │                          │
                   │             ▼                          │
                   │    ┌──────────────────┐                │
                   │    │                  │                │
                   ├────│ ventilation_     │────┐           │
                   │    │ recommended      │    │           │
                   │    │                  │    │           │
                   │    └──────────────────┘    │           │
                   │                            │           │
                   │                     outdoor ≥ indoor + 1.0°C
                   │                            │           │
                   │                            ▼           │
                   │    ┌──────────────────┐                │
                   │    │                  │                │
                   └────│  close_windows   │────────────────┘
                        │                  │  both sensors
                        └──────────────────┘  unavailable
```

Transitions:
- `normal` → `ventilation_recommended`: outdoor ≤ indoor − 1.0°C
- `ventilation_recommended` → `close_windows`: outdoor ≥ indoor + 1.0°C
- `close_windows` → `ventilation_recommended`: outdoor ≤ indoor − 1.0°C
- Any non-normal → `normal`: both sensors unavailable (sensor recovery fallback)
- One sensor unavailable / no delta match: no transition (stay in current state)

### Trigger
```yaml
triggers:
  - trigger: state
    entity_id: sensor.switchbot_indoor_temperature
  - trigger: state
    entity_id: sensor.switchbot_outdoor_temperature
```

### Core state machine template
```yaml
variables:
  indoor: "{{ states('sensor.switchbot_indoor_temperature') }}"
  outdoor: "{{ states('sensor.switchbot_outdoor_temperature') }}"
  cur: >-
    {% set s = states('input_select.ventilation_state') %}
    {% if s in ['normal','ventilation_recommended','close_windows'] %}{{ s }}
    {% else %}normal{% endif %}
  ibad: "{{ indoor in ['unavailable','unknown','none'] }}"
  obad: "{{ outdoor in ['unavailable','unknown','none'] }}"
  numeric: "{{ (indoor | float(-999)) != -999 and (outdoor | float(-999)) != -999 }}"
  delta: "{{ (outdoor | float(-999)) - (indoor | float(-999)) }}"
  target: >-
    {% if ibad and obad %}normal
    {% elif not ibad and not obad and numeric
      and ( (cur == 'normal' and delta <= -1.0) or
            (cur == 'ventilation_recommended' and delta >= 1.0) or
            (cur == 'close_windows' and delta <= -1.0) )
    %}
      {% if delta <= -1.0 %}ventilation_recommended
      {% elif delta >= 1.0 %}close_windows
      {% endif %}
    {% else %}{{ cur }}{% endif %}
```

Then on transition (`target != cur`):
- Update `input_select.ventilation_state` to `target`
- If `ventilation_recommended`: notify + persistent_notification "Abre las ventanas — está más fresco fuera que dentro."
- If `close_windows`: notify + persistent_notification "Cierra las ventanas — está más caliente fuera que dentro."
- If `normal`: no notification (R2.6)

## input_select definition (configuration.yaml)

```yaml
input_select:
  ventilation_state:
    name: "Ventilación - Estado"
    options:
      - normal
      - ventilation_recommended
      - close_windows
    initial: normal
    icon: "mdi:window-open-variant"
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `ha-config/automations.yaml` | Modify | Replace automation `1749052800002` (lines 129-201) with `fan-study-temperature-control` |
| `ha-config/automations.yaml` | Add | New `ventilation-notifications` automation (appended) |
| `ha-config/configuration.yaml` | Modify | Add `input_select.ventilation_state` (alongside existing `input_boolean` definitions) |

## Edge Cases

| Edge case | Handling |
|-----------|----------|
| Sensor unavailable (fan-control) | Checked first in choose → log warning, no speed change (R1.5) |
| Both sensors unavailable (ventilation) | Transition to `normal` from any non-normal state (R2.3) |
| One sensor unavailable (ventilation) | Stay in current state — no transition (R2.9) |
| Non-numeric sensor reading | Treat as unavailable via `float(-999)` fallback (R2.10) |
| Notification service failure | State updated first (critical path); notification is secondary. If notify fails, state is correct. (R2 failure mode 6) |
| input_select entity unavailable | Template defaults to `normal` (graceful degradation) |
| Simultaneous quiet hours + <24°C | `<24°C → OFF` evaluated before quiet hours cap → OFF wins (R1.4 lowest-value rule) |
| System timezone | HA timezone as configured. Quiet hours evaluated in HA timezone. |

## Testing Strategy

| Layer | What | How |
|-------|------|-----|
| Boundary | Temp band boundaries | Set sensor to each boundary value via Developer Tools, invoke automation, verify speed |
| Boundary | Quiet hours boundaries | Test at 22:59 vs 23:00, 07:59 vs 08:00 with T=30°C |
| Guard | Fan OFF → no action | Turn fan OFF, trigger automation, verify speed unchanged |
| Guard | Sensor unavailable | Set sensor to `unavailable`, trigger, verify no speed change |
| State machine | All transitions | Set temp delta to trigger each transition, verify state + notification |
| State machine | No duplicate notification | Re-trigger same state, verify no new notification |
| State machine | Hysteresis | Set delta to -0.9°C (no transition), -1.0°C (transition), swing back to -0.9°C (no transition back) |
| State machine | Both sensors unavailable | Set both to `unavailable`, verify transition to `normal`, no notification |
| Failure | One sensor unavailable | Set indoor to `unavailable`, outdoor to 25.0, verify no state transition |

## Migration / Rollout

1. Add `input_select.ventilation_state` to `configuration.yaml`
2. Restart HA (or reload core config)
3. Verify `input_select.ventilation_state` exists in Developer Tools → States (initial: `normal`)
4. Replace automation `1749052800002` with new `fan-study-temperature-control` in `automations.yaml`
5. Add `ventilation-notifications` automation to `automations.yaml`
6. Reload automations via HA Developer Tools → YAML → reload automations
7. Verify: no YAML validation errors in HA logs
8. Test each acceptance criterion

Rollback: `git checkout main -- ha-config/automations.yaml ha-config/configuration.yaml` + reload automations + core config.
