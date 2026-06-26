# Tasks: ha-night-purge-49 — Night Purging

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~130 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Add input_boolean helpers (config) | PR 1 | Base: main. Standalone. |
| 2 | Phase 1 night opening automation | PR 1 | Appended after Unit 1 |
| 3 | Phase 2 morning closing automation | PR 1 | Appended after Unit 2 |
| 4 | Verify syntax and scenarios | PR 1 | Run HA config check |

## Phase 1: Foundation — Configuration

- [x] **1.1** Extend existing `input_boolean:` block in `ha-config/configuration.yaml` (line 47) with `modo_ventilacion_nocturna` (name: "Night purge - Modo activo", icon: "mdi:weather-night"), `ventanas_abiertas` (name: "Night purge - Ventanas abiertas", icon: "mdi:window-open"), and `night_purge_skip_today` (name: "Night purge - Saltar hoy", icon: "mdi:cancel") under a `# NIGHT PURGE` section comment.

## Phase 2: Core Implementation — Automations

- [x] **2.1** Create Phase 1 automation (`id: '1768000000003'`) at end of `ha-config/automations.yaml`: time_pattern `/15`, time 21:00–00:00 (3 windows), conditions toggle on / skip off / ventanas off / indoor > 24°C / outdoor < indoor / sensors available. Notify.send_message to both phones (informational), then notify.mobile_app_alejandros_iphone with actions `NIGHT_PURGE_OPENED` / `NIGHT_PURGE_SKIP_TODAY`. `wait_for_trigger` 15 min, `continue_on_timeout: true`. On OPENED → turn_on ventanas_abiertas, on SKIP_TODAY → turn_on night_purge_skip_today.

- [x] **2.2** Create Phase 2 automation (`id: '1768000000004'`) appended after Phase 1: time_pattern `/15`, time 07:00–10:00 (3 windows), conditions toggle on / ventanas on / outdoor >= indoor / sensors available. Notify.send_message to both phones, then notify.mobile_app_alejandros_iphone with action `NIGHT_PURGE_CLOSED`. `wait_for_trigger` 15 min, `continue_on_timeout: true`. On trigger → `input_boolean.turn_off ventanas_abiertas`.

## Phase 3: Verification

- [ ] **3.1** Validate YAML syntax: `ha config check` or `python -m homeassistant -c ha-config --script check_config`. Verify Phase 1 fires with simulated 22:00 / indoor 26°C / outdoor 22°C / toggle on / ventanas off. Verify Phase 2 fires with simulated 08:00 / ventanas on / outdoor 24°C / indoor 22°C. Verify both abort when sensors are unavailable. Verify toggle off suppresses all.

### Implementation Order

Phase 1 config must come first (automations reference the new entities). Phase 2 depends on Phase 1 entities existing. Phase 3 (verification) is last.

### Assessment: Combine TASK-002 and TASK-003?

Keep separate. Each is ~55-60 lines with distinct conditions and logic. Independent review per automation. The existing codebase separates concerns the same way (ventilation and air quality are separate automations).
