# Proposal: ha-night-purge-49 — Night purging con sensores indoor + outdoor

## Intent

Summer nights in Madrid stay hot indoors even when outside cools down. The existing ventilation automation (`1768000000001`) notifies on temp delta 24/7 but lacks time gating and window state tracking. Night purging adds: (1) after-dark recommendations when indoor > 24°C and outdoor < indoor, (2) morning close reminders when outdoor warms back up, and (3) actionable notifications to track actual window state — so the system knows windows are open before suggesting to close them.

## Scope

### In Scope
- **Phase 1** (Night open): After 21:00, if outdoor < indoor AND indoor > 24°C, notify "Hace más fresco afuera que adentro. Abrí las ventanas para ventilar/enfriar" with actionable buttons.
- **Phase 2** (Morning close): After 07:00, if outdoor >= indoor AND `input_boolean.ventanas_abiertas` is on, notify "Ya está más caliente afuera que adentro. Cerrá las ventanas."
- `input_boolean.ventanas_abiertas` — set via notification action "Ya abrí" (Phase 1) or "Ya cerré" (Phase 2). Auto-off after Phase 2 close notification action.
- `input_boolean.modo_ventilacion_nocturna` — master enable toggle for both phases.
- Actionable notification pattern (data.actions + wait_for_trigger, following termo gym pattern).

### Out of Scope
- **Phase 3** (Daytime comfort > 28°C with fan/shade suggestion): deferred — stretch goal.
- Modifying existing `input_select.ventilation_state` or automation `1768000000001`.
- Auto-control of windows/fans (manual action only).
- Integration with weather forecast or sunrise/sunset (fixed times).

## Capabilities

### New Capabilities
- `night-purge`: Time-gated night ventilation recommendation with actionable window state tracking using `input_boolean.ventanas_abiertas` and `input_boolean.modo_ventilacion_nocturna`.

### Modified Capabilities
- None.

## Approach

1. **Helpers**: Add `input_boolean.ventanas_abiertas` (off/on) and `input_boolean.modo_ventilacion_nocturna` (off/on, default off) in `configuration.yaml`.
2. **Phase 1 automation**: Time_pattern trigger every 15 min during 21:00–07:00. Conditions: modo on, indoor > 24°C, outdoor < indoor, ventanas_abiertas off (skip if already open). Send actionable notification with "Ya abrí" / "No ahora" actions. On "Ya abrí" → set ventanas_abiertas on.
3. **Phase 2 automation**: Time_pattern trigger every 15 min during 07:00–21:00. Conditions: modo on, ventanas_abiertas on, outdoor >= indoor. Send actionable notification with "Ya cerré" action. On "Ya cerré" → set ventanas_abiertas off.
4. **Dedup**: State checks prevent re-notifying — Phase 1 only fires if ventanas_abiertas is off; Phase 2 only if it's on.
5. **Existing auto untouched**: `1768000000001` continues to notify on temp delta anytime; night purge adds time + window state awareness without modifying it.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `ha-config/configuration.yaml` | Modified | Add 2 `input_boolean` helpers |
| `ha-config/automations.yaml` | Modified | Add 2 new automations (Phase 1 + Phase 2) |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Both existing auto + night purge notify simultaneously near 21:00 | Low | Different trigger mechanics; dedup via state checks. If both fire, messages are complementary (same recommendation). |
| Actionable notification timeout (user asleep) | Med | Phase 1 sets reasonable timeout. No-action is safe — windows stay as they were. |
| modo_ventilacion_nocturna default off means feature inactive until user enables | Low | Intentional — opt-in by design (safety). |

## Rollback Plan

Revert the two YAML files:
```
git checkout main -- ha-config/automations.yaml ha-config/configuration.yaml
```
The two `input_boolean` entities left in HA state are harmless — delete via Developer Tools > States if desired.

## Dependencies

- `sensor.indoor_outdoor_meter_1c24_temperatura` and `sensor.meter_pro_co2_9540_temperatura` already reporting
- `notify.mobile_app_alejandros_iphone` and `notify.mobile_app_miriam_iphone` already configured
- Actionable notification pattern already proven in termo gym automation

## Success Criteria

- [ ] Phase 1: After 21:00 with indoor > 24°C and outdoor < indoor, notification received with "Ya abrí" / "No ahora" buttons
- [ ] Phase 2: After 07:00 with ventanas_abiertas on and outdoor >= indoor, notification received
- [ ] Tapping "Ya abrí" sets `input_boolean.ventanas_abiertas` to on; "Ya cerré" sets it off
- [ ] Toggle `input_boolean.modo_ventilacion_nocturna` off suppresses all night purge notifications
- [ ] No modifications to existing automation `1768000000001` behavior
