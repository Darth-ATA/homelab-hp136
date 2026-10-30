# Verify: ha-air-quality-47 — Air Quality Notifications

## Verdict: FAIL

**CRITICAL bug found**: Sensor unavailability while in `bad` state sends a false "air quality recovered" notification. This directly violates REQ-006 and Scenario 4.

---

## Requirements Compliance

| ID | Requirement | Status | Notes |
|----|-------------|--------|-------|
| REQ-001 | Bad air quality detection | ✅ COMPLIANT | CO₂ > 1000 ppm with 5-min debounce triggers normal→bad. State machine logic correct. |
| REQ-002 | Air quality recovery notification | ✅ COMPLIANT | CO₂ < 800 ppm with 5-min debounce triggers bad→normal. Correct recovery message sent. |
| REQ-003 | No notification spam | ✅ COMPLIANT | `target != cur` guard prevents re-notification while state is unchanged. `for: 5 min` prevents flapping. |
| REQ-004 | Notify both phones | ⚠️ PARTIAL | Targets `notify.mobile_app_alejandros_iphone` and `notify.miriam_iphone`. Spec says `notify.mobile_app_miriam_iphone` — entity ID mismatch (see Warning #1). |
| REQ-005 | Notification content | ✅ COMPLIANT | Messages in español ibérico (tú form). Bad air asks to open windows. Recovery says air is good again. |
| REQ-006 | Sensor unavailability handling | ❌ FAILING | **CRITICAL**: Sensor unavailable while state is `bad` triggers false recovery notification (see Critical #1). |

## Acceptance Criteria

| Scenario | Status | Notes |
|----------|--------|-------|
| Scenario 1: Bad air quality | ✅ PASS | CO₂ > 1000 for 5 min → state to `bad` → notification to both phones. No re-notification while bad. |
| Scenario 2: Air quality recovery | ✅ PASS | CO₂ < 800 for 5 min while `bad` → state to `normal` → recovery notification to both phones. |
| Scenario 3: No spam on fluctuation | ✅ PASS | `for: minutes: 5` on state trigger resets on each state change. Fluctuating values don't meet duration. Hysteresis gap (800-1000) prevents boundary oscillations. |
| Scenario 4: Sensor unavailable | ❌ FAIL | **CRITICAL**: Sensor unavailable while state is `bad` fires recovery notification claiming "air has improved". REQ-006 requires no notification for unavailable sensor. |

## Issues Found

### CRITICAL — False recovery notification on sensor unavailability

**Description**: When the CO₂ sensor reports `unavailable`/`unknown`/`none` AND `input_select.air_quality_state` is currently `bad`, the automation triggers a false recovery notification. The `target` variable resolves to `'normal'` (line 624: `{% if co2bad %}normal`), which differs from `cur` (`'bad'`), so the notification action for `target == 'normal'` fires (lines 658-675). The user receives "La calidad del aire ha mejorado. Ya puedes cerrar las ventanas." — but the air hasn't improved, the sensor just went offline.

**Location**: `ha-config/automations.yaml`, lines 623-624:
```yaml
target: >-
  {% if co2bad %}normal
```

**Root cause**: Unlike the ventilation automation (id: `1768000000001`), which also sets `target: normal` when sensors are unavailable but has NO notification action for the `normal` target, this automation DOES have a notification for `normal` (the recovery message). So the unavailability handling logic is copied from the ventilation pattern but adapted incorrectly.

**Fix**: Change line 624 from `{% if co2bad %}normal` to `{% if co2bad %}{{ cur }}` — this preserves the current state when the sensor is unavailable, preventing any state transition or notification:

```yaml
      target: >-
        {% if co2bad %}{{ cur }}
        {% elif (co2 | float(-999)) > 1000 and cur == 'normal' %}bad
        {% elif (co2 | float(-999)) < 800 and cur == 'bad' %}normal
        {% else %}{{ cur }}{% endif %}
```

With this fix:
- `bad` → sensor unavailable → `target = cur = 'bad'` → no transition → no notification ✅
- `normal` → sensor unavailable → `target = cur = 'normal'` → no transition → no notification ✅
- Normal bad/recovery transitions unaffected ✅

### WARNING — Spec deviation for Miriam's notification entity ID

**Description**: REQ-004 specifies `notify.mobile_app_miriam_iphone` as the notification channel for Miriam. The implementation uses `notify.miriam_iphone` (lines 651, 670). The existing codebase is inconsistent — the ventilation automation (id: `1768000000001`, lines 577, 594) uses `notify.mobile_app_miriam_iphone`, while the newer lavadora automations (lines 319, 338, 356, 393, 432, 511) use `notify.miriam_iphone`.

**Location**: `ha-config/automations.yaml`, lines 651 and 670.

**Recommendation**: Verify which entity ID exists in HA Developer Tools → Services. If `notify.miriam_iphone` is the correct ID (as the newer lavadora code uses), update the spec (REQ-004) to match. If `notify.mobile_app_miriam_iphone` is correct, fix the implementation.

### SUGGESTION — Non-numeric sensor state edge case

**Description**: If the sensor reports a non-numeric value outside the `['unavailable', 'unknown', 'none']` set (e.g., `'error'`, `'disconnected'`), `float(-999)` returns `-999`, and the check `(co2 | float(-999)) < 800` evaluates to `true` because `-999 < 800`. If `cur` is `'bad'`, this would trigger a false recovery notification.

**Location**: `ha-config/automations.yaml`, line 626.

**Mitigation**: Low risk — the Switchbot Meter Pro CO₂ sensor only reports numeric CO₂ values or the known unavailable states. The ventilation automation uses the same `float(-999)` pattern. Can be addressed in a future hardening pass by adding a `is_number` check before numeric comparisons.

## Code Quality Review

| Aspect | Rating | Notes |
|--------|--------|-------|
| Pattern consistency | ✅ Good | Follows the same structure as the ventilation automation (variables → if target != cur → choose with notifications). Comment headers match project style. |
| Error handling | ⚠️ Needs fix | CRITICAL bug for sensor unavailable in `bad` state (see above). Otherwise, the `in ['unavailable', 'unknown', 'none']` check pattern is correct. |
| Readability | ✅ Good | Clear variable names (`co2`, `cur`, `co2bad`, `target`). Logic is easy to follow. |
| Naming consistency | ✅ Good | `input_select.air_quality_state`, `air_quality_bad`, `air_quality_normal` — consistent naming throughout. |
| Spec-item alignment | ✅ Good | All items match spec except the `notify.miriam_iphone` entity ID issue. |

## Detailed Technical Analysis

### State Machine Trace (Normal Operation)

| Current State | Sensor Value (5 min) | Target | Notification |
|---|---|---|---|
| `normal` | 450 ppm | `normal` | None (no transition) |
| `normal` | 1200 ppm | `bad` | "Abre las ventanas para ventilar" |
| `bad` | 1200 ppm | `bad` | None (no transition) |
| `bad` | 700 ppm | `normal` | "La calidad del aire ha mejorado" |
| `normal` | 900 ppm | `normal` | None (hysteresis gap) |

### State Machine Trace (Sensor Unavailability — THE BUG)

| Current State | Sensor Value (5 min) | Target | Actual Behavior | Expected Behavior |
|---|---|---|---|---|
| `normal` | `unavailable` | `normal` | No notification ✅ | No notification ✅ |
| `bad` | `unavailable` | `normal` | **Sends recovery notification ❌** | No notification ✅ |
| `bad` | `unknown` | `normal` | **Sends recovery notification ❌** | No notification ✅ |
| `normal` | `unknown` | `normal` | No notification ✅ | No notification ✅ |

### YAML Validation
- `automations.yaml`: ✅ Valid YAML (confirmed with `yaml.safe_load`)
- `configuration.yaml`: ✅ Structurally valid. The `!include` directive is an HA extension — standard parsers reject it, but HA handles it correctly. The input_select block is independently valid.

### Automation ID Uniqueness
- `1768000000002`: ✅ Unique. No collision with `1768000000001` (ventilation) or `1768000000000` (circadiana fan). String-based lavadora IDs are in a different namespace.

### Commit History
- `fcbb5bb` — `feat(ha-config): add air_quality_state input_select for air quality monitoring` ✅
- `a1b6119` — `feat(ha-config): add air quality notifications automation for CO2 levels` ✅

---

## Summary

**The implementation is well-structured and matches the spec for most requirements**, but has a **CRITICAL bug** that violates REQ-006: when the CO₂ sensor becomes unavailable while the state machine is in `bad`, the automation sends a false "air quality recovered" notification. This is a one-line fix (change `normal` to `{{ cur }}` on line 624).

**Issues**: 1 critical, 1 warning, 1 suggestion

### What needs fixing before PR
1. **Line 624 of `automations.yaml`**: Change `{% if co2bad %}normal` to `{% if co2bad %}{{ cur }}` to prevent false recovery notifications on sensor unavailability.
2. **Verify `notify.miriam_iphone` exists** in HA — either confirm the entity ID or fix to `notify.mobile_app_miriam_iphone` per spec.
