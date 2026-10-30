# Design: Night Purge — ha-night-purge-49

## Technical Approach

Two new automations plus two `input_boolean` helpers implement time-gated night cooling. Follows existing patterns: temp sensor validation (from `1768000000001`), actionable notifications with `wait_for_trigger` (from termo gym `1743833516442`). Phase 1 (21:00–07:00) suggests opening windows when outdoor < indoor and indoor > 24°C. Phase 2 (07:00–21:00) suggests closing when outdoor >= indoor and windows tracked as open. Both respect master toggle `modo_ventilacion_nocturna`.

## Architecture Decisions

### Decision: Actionable notification pattern

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Send + wait_for_trigger in same automation (termo gym style) | Clean, single automation per phase. `continue_on_timeout: true` prevents blocking. | **Chosen** — simplest, proven pattern |
| Separate event handler automation (lavadora style) | Decouples send from response. More files, more state. | Rejected — over-engineered for two phases |

### Decision: Anti-spam strategy

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Only state checks | If user taps "No ahora", next 15-min cycle re-notifies. Could annoy. | **Chosen** — spec-aligned. User can toggle mode off for full dismissal |
| Add `input_boolean.notified_tonight` + auto-reset | More entities, more complexity. | Rejected — scope creep |

### Decision: Both phones actionable

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Both phones get action buttons | Either can respond. `wait_for_trigger` catches response from any device. | **Chosen** — spec requirement, works with HA event model |
| Only Ale receives actions, Miriam info-only | Simpler `wait_for_trigger` (single device). | Rejected — contradicts spec. Can be revisited if phantom triggers occur |

### Decision: Automation IDs

Use sequential `1768...` IDs following the ventilation family convention: Phase 1 = `1768000000003`, Phase 2 = `1768000000004`.

## Data Flow

```
┌──────────────┐     time_pattern /15      ┌─────────────────────┐
│  Both temp    │ ──── state change ──────→ │  Phase 1 or Phase 2  │
│    sensors    │                           │    Automation        │
└──────────────┘                           └──────────┬──────────┘
                                                       │
                              ┌────────────────────────┼────────────┐
                              │                        │            │
                              ▼                        ▼            ▼
                   ┌─────────────────┐    ┌───────────────────┐   ┌───┐
                   │ Ale's phone     │    │ Miriam's phone    │   │   │
                   │ (actionable)    │    │ (actionable)      │   │skip│
                   └────────┬────────┘    └─────────┬─────────┘   └───┘
                            │                       │
                            └───────────┬───────────┘
                                        │  mobile_app_notification_action
                                        ▼  event
                              ┌─────────────────────┐
                              │  wait_for_trigger    │
                              │  30 min timeout      │
                              │  continue_on_timeout │
                              └──────────┬──────────┘
                                         │ trigger (opened/closed)
                                         ▼
                              ┌─────────────────────┐
                              │  input_boolean.     │
                              │  ventanas_abiertas  │
                              │  on / off           │
                              └─────────────────────┘
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `ha-config/configuration.yaml` | Modify | Add 2 `input_boolean` entries after line 59 (after lavadora block) |
| `ha-config/automations.yaml` | Modify | Append 2 new automations at end of file |

## Entities

```yaml
input_boolean:
  modo_ventilacion_nocturna:
    name: "Ventilación nocturna"
    icon: "mdi:weather-night"
  ventanas_abiertas:
    name: "Ventanas abiertas"
    icon: "mdi:window-open"
```

## Automation Design (Pseudocode)

### Phase 1: Night Opening (`1768000000003`)

```
TRIGGER: time_pattern minutes:/15
CONDITIONS:
  - modo_ventilacion_nocturna == on
  - ventanas_abiertas == off
  - time >= 21:00 OR time < 07:00
  - indoor > 24°C (numeric_state)
  - outdoor < indoor (template)
  - both sensors available (template — checks unavailable/unknown/none)
ACTIONS:
  1. notify.mobile_app_alejandros_iphone:
       title "🌙 Ventilación nocturna"
       message "Hace más fresco fuera que dentro. Abre las ventanas para ventilar la casa."
       tag: night_purge_phase1
       actions: [{action: NIGHT_PURGE_OPENED, title: "Ya he abierto"},
                 {action: NIGHT_PURGE_SKIP, title: "No ahora"}]
  2. notify.mobile_app_miriam_iphone: (same content)
  3. wait_for_trigger: mobile_app_notification_action with action NIGHT_PURGE_OPENED
     timeout: 30 min, continue_on_timeout: true
  4. if wait.trigger is not none → input_boolean.turn_on ventanas_abiertas
```

### Phase 2: Morning Closing (`1768000000004`)

```
TRIGGER: time_pattern minutes:/15
CONDITIONS:
  - modo_ventilacion_nocturna == on
  - ventanas_abiertas == on
  - time >= 07:00 AND time < 21:00
  - outdoor >= indoor (template)
  - both sensors available
ACTIONS:
  1. notify to both phones:
       title "☀️ Cierre matutino"
       message "Ya está más caliente fuera que dentro. Cierra las ventanas para mantener el fresco."
       tag: night_purge_phase2
       actions: [{action: NIGHT_PURGE_CLOSED, title: "Ya he cerrado"}]
  2. wait_for_trigger: mobile_app_notification_action with action NIGHT_PURGE_CLOSED
     timeout: 30 min, continue_on_timeout: true
  3. if wait.trigger is not none → input_boolean.turn_off ventanas_abiertas
```

## Sensor Unavailability Check

Follows existing pattern from `1768000000001` (line 541):

```yaml
- condition: template
  value_template: >
    {{ states('sensor.meter_pro_co2_9540_temperatura') not in ['unavailable', 'unknown', 'none']
       and states('sensor.indoor_outdoor_meter_1c24_temperatura') not in ['unavailable', 'unknown', 'none'] }}
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| YAML syntax | Both new automations + modified configuration | `home-assistant -c ha-config --script check_config` or similar |
| Phase 1 logic | Conditions fire correctly at night | Simulate time + temp values, verify notify fires |
| Phase 2 logic | Conditions fire correctly in morning | Simulate time + temp values, verify notify fires |
| Actionable buttons | Tapping updates state | Real device test post-deploy |

## Migration / Rollout

No migration required. Automations start idle (master toggle defaults to `off`). User enables via HA dashboard.

## Open Questions

None — all decisions resolved in spec and this design.
