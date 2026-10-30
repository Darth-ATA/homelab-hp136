# Proposal: ha-air-quality-47 — Study CO2 air quality notifications

## Intent

The Switchbot Meter Pro CO2 9540 in the study can measure CO₂ levels but nobody gets notified when air quality degrades. Without awareness of rising CO₂, we work in stale air — reduced focus, headaches, sleepiness. We need push notifications when air quality is bad (open windows) and when it recovers (close windows), with dedup to avoid spam.

## Scope

### In Scope
- Push notification when CO₂ exceeds 1000 ppm: "open windows"
- Push notification when CO₂ drops below 800 ppm from bad state: "OK to close windows"
- `input_select.air_quality_state` state machine (normal / bad / recovery) for dedup
- Notifications to BOTH phones (Alejandro + Miriam)

### Out of Scope
- CO₂ history dashboard or graphs
- Any integration with existing `input_select.ventilation_state` (separate concern)
- Auto-control of fans or windows (manual action only)
- Other rooms or CO₂ sensors

## Capabilities

### New Capabilities
- `air-quality-notification`: Monitor study CO₂ levels and notify user(s) when bad (>1000 ppm) and when recovered (<800 ppm), using state machine to fire only on transitions.

### Modified Capabilities
- None.

## Approach

1. **State machine**: New `input_select.air_quality_state` (normal / bad). Initial: `normal`.
2. **Trigger**: On change of `sensor.meter_pro_co2_9540_dioxido_de_carbono`.
3. **Bad air**: If CO₂ > 1000 AND current state is `normal` → set state to `bad`, notify both phones (Alejandro + Miriam).
4. **Recovery**: If CO₂ < 800 AND current state is `bad` → set state to `normal`, notify "air quality recovered" to both phones.
5. **Stale handling**: If CO₂ is between 800-1000, do nothing — only fire on transition boundaries.
6. **Debounce**: Use `for: 00:05:00` on the numeric_state trigger to avoid flapping.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `ha-config/configuration.yaml` | Modified | Add `input_select.air_quality_state` |
| `ha-config/automations.yaml` | Modified | Add new air quality automation |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| CO₂ sensor unavailable (battery dead, disconnect) | Med | `for: 5 min` debounce; numeric_state already handles unavailable gracefully |
| Notification spam during sensor drift near threshold | Low | Separate state machine prevents re-notification; 800/1000 ppm hysteresis gap |

## Rollback Plan

Revert `automations.yaml` and `configuration.yaml`:
```
git checkout main -- ha-config/automations.yaml ha-config/configuration.yaml
```
The `input_select.air_quality_state` entity left in HA state is harmless — it will show "normal" indefinitely.

## Dependencies

- `sensor.meter_pro_co2_9540_dioxido_de_carbono` already reporting data
- `notify.mobile_app_alejandros_iphone` and `notify.mobile_app_miriam_iphone` already configured

## Success Criteria

- [ ] Push notification received on BOTH phones when CO₂ > 1000 ppm in the study
- [ ] Recovery notification received on BOTH phones when CO₂ drops below 800 ppm (only if previously in bad state)
- [ ] No duplicate notifications within same state (state machine prevents re-fire)
- [ ] Sensor unavailable does not trigger false notifications
