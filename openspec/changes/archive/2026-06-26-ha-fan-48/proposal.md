# Proposal: ha-fan-48 — Study ceiling fan with real temperature sensors

## Intent

Replace time-of-day + solar elevation proxy with actual Switchbot temperature readings for study fan speed. Add smart cross-ventilation notifications comparing indoor vs outdoor temp to guide manual window management.

## Scope

### In Scope
- Temperature-based speed (5 bands: <24°C → off, 24-26 → 25%, 26-28 → 50%, 28-30 → 75%, >30 → 100%)
- Cross-ventilation notifications (open/close windows based on indoor/outdoor delta)
- `input_select.ventilation_state` state machine for notification dedup
- Quiet hours (23:00-08:00) capping speed at 25%

### Out of Scope
- Auto-turn-on (no presence sensor)
- Other rooms or fans
- Sensor hardware setup

## Capabilities

### New Capabilities
- `fan-study-temperature-control`: Temp-based fan speed. Only acts when fan is ON. Quiet hours cap at 25%.
- `ventilation-notifications`: Notify to open windows when outdoor < indoor - 1°C ("Abre las ventanas — está más fresco fuera que dentro"). Notify to close when outdoor > indoor + 1°C ("Cierra las ventanas — está más caliente fuera que dentro"). Dedup via state machine.

### Modified Capabilities
- None.

## Approach

1. **Trigger**: `time_pattern` → temperature change triggers on both sensors with `for: 00:05:00` debounce.
2. **Guard**: Keep existing ON condition.
3. **Speed logic**: Map time branches to temperature ranges. Quiet hours override evaluated first.
4. **Notifications**: Compare indoor vs outdoor on change. Use `input_select.ventilation_state` (normal/ventilation_recommended/close_windows) to notify only on transition. Send via `mobile_app` to Alejandro.
5. **Test**: Verify each band via `homeassistant.update_entity` in Developer Tools.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `ha-config/automations.yaml` | Modified | Lines 113-201: replace `Circadiana` fan logic |
| `ha-config/automations.yaml` | New | Cross-ventilation automation |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|-------------|
| Sensor unavailable (battery/disconnect) | Med | Keep current speed if no temp data |
| Notification spam during temp swings | High | `input_select` state machine + transition-only alerts |
| Quiet hours boundary race | Low | 25% override evaluated first; inclusive bounds |

## Rollback Plan

Revert `automations.yaml`:
```
git checkout main -- ha-config/automations.yaml
```
`input_select.ventilation_state` left in state is harmless.

## Dependencies

- `sensor.switchbot_indoor_temperature` reporting
- `sensor.switchbot_outdoor_temperature` reporting
- `input_select.ventilation_state` entity created in HA

## Success Criteria

- [ ] Fan speed matches temp bands ±1°C (verified via Developer Tools)
- [ ] Quiet hours: speed never exceeds 25% between 23:00-08:00
- [ ] Each ventilation notification fires exactly once per state transition
- [ ] Fan never turns on automatically when temp changes while OFF
- [ ] State machine transitions: normal → ventilation_recommended → normal → close_windows → normal
