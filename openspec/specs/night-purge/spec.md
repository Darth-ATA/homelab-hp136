# Night Purge Specification

Time-gated night cooling automation: recommends opening windows when outdoor air is cooler (Phase 1), closing before morning heat returns (Phase 2). Controlled by master toggle with window state tracking.

## Entities

| Entity | Type | Default | Purpose |
|--------|------|---------|---------|
| `input_boolean.modo_ventilacion_nocturna` | input_boolean | off | Master toggle |
| `input_boolean.ventanas_abiertas` | input_boolean | off | Windows reported as open |

## Requirements

### Requirement 1: Master Toggle

System MUST NOT execute night purge unless `modo_ventilacion_nocturna` is `on`.

#### Scenario: Toggle disables all

- GIVEN `modo_ventilacion_nocturna` is `off`
- WHEN Phase 1 or Phase 2 conditions are met
- THEN no notification, no state changes

### Requirement 2: Night Opening (Phase 1)

| Condition | Threshold | Source |
|-----------|-----------|--------|
| Time | 21:00–07:00 | time_pattern 15 min |
| Indoor > 24°C | > 24°C | `sensor.meter_pro_co2_9540_temperatura` |
| Outdoor < Indoor | outdoor < indoor | `sensor.indoor_outdoor_meter_1c24_temperatura` |
| Windows closed | `ventanas_abiertas` is `off` | `input_boolean.ventanas_abiertas` |

Both phones receive actionable notification: **title** "🌙 Ventilación nocturna", **message** "Hace más fresco fuera que dentro. Abre las ventanas para ventilar la casa.", **actions** `NIGHT_PURGE_OPENED` ("Ya he abierto") / `NIGHT_PURGE_SKIP` ("No ahora"), **timeout** 30 min.

#### Scenario: Notification fires

- GIVEN 22:00, indoor 26°C, outdoor 22°C, `ventanas_abiertas` off, toggle on
- WHEN time_pattern triggers
- THEN actionable notification sent to both phones

#### Scenario: "Ya he abierto" opens windows

- GIVEN night notification active
- WHEN user taps "Ya he abierto"
- THEN `ventanas_abiertas` set to `on`

#### Scenario: Skip does nothing

- GIVEN night notification active
- WHEN user taps "No ahora"
- THEN `ventanas_abiertas` unchanged

#### Scenario: Already open, no re-notify

- GIVEN `ventanas_abiertas` is `on`
- WHEN time_pattern fires again within same night
- THEN no notification

### Requirement 3: Morning Closing (Phase 2)

| Condition | Threshold | Source |
|-----------|-----------|--------|
| Time | 07:00–21:00 | time_pattern 15 min |
| Windows open | `ventanas_abiertas` is `on` | `input_boolean.ventanas_abiertas` |
| Outdoor ≥ Indoor | outdoor ≥ indoor | temperature sensors |
| Master enabled | `modo_ventilacion_nocturna` is `on` | `input_boolean.modo_ventilacion_nocturna` |

Both phones receive actionable notification: **title** "☀️ Cierre matutino", **message** "Ya está más caliente fuera que dentro. Cierra las ventanas para mantener el fresco.", **actions** `NIGHT_PURGE_CLOSED` ("Ya he cerrado"), **timeout** 30 min.

#### Scenario: Notification fires

- GIVEN 08:00, indoor 22°C, outdoor 24°C, `ventanas_abiertas` on, toggle on
- WHEN time_pattern triggers
- THEN actionable notification sent to both phones

#### Scenario: "Ya he cerrado" clears state

- GIVEN morning notification active
- WHEN user taps "Ya he cerrado"
- THEN `ventanas_abiertas` set to `off`

#### Scenario: Already closed, no re-notify

- GIVEN `ventanas_abiertas` is `off`
- WHEN time_pattern fires again within same morning
- THEN no notification

### Requirement 4: Sensor Unavailability

If either temp sensor is `unavailable` or non-numeric, automation MUST abort silently.

#### Scenario: Indoor sensor unavailable

- GIVEN `sensor.meter_pro_co2_9540_temperatura` is `unavailable`
- WHEN conditions otherwise met
- THEN no notification

#### Scenario: Outdoor sensor unavailable

- GIVEN `sensor.indoor_outdoor_meter_1c24_temperatura` non-numeric
- WHEN conditions otherwise met
- THEN no notification

## Delivery

Standard messages use `notify.send_message` with `target.entity_id` list. Actionable notifications (with `wait_for_trigger`) use individual `notify.mobile_app_*` sent in parallel to both phones.
