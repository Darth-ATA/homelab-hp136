## Verification Report

**Change**: ha-night-purge-49
**Spec Version**: 1.0 (openspec/specs/night-purge/spec.md)
**Mode**: Standard (no TDD)

### Completeness
| Metric | Value |
|--------|-------|
| Tasks total | 4 |
| Tasks complete | 4 (all marked [x] in tasks.md) |
| Tasks incomplete | 0 |
| Commits | 4 (b619be7, 8d4a0a5, f41d705, a0506cc) |

### YAML Syntax Verification
**Build**: ✅ Passed (both files valid YAML)

```text
$ python3 yaml.load with FullLoader + !include constructors
ha-config/configuration.yaml: ✅ Valid YAML
ha-config/automations.yaml: ✅ Valid YAML
All YAML files valid.
```

**Duplicate IDs**: ✅ None found — 13 automations, all IDs unique.
```
1768000000003 → Night purge: Apertura nocturna
1768000000004 → Night purge: Cierre matutino
```

### Spec Compliance Matrix

| Requirement | Scenario | Evidence | Result |
|-------------|----------|----------|--------|
| R1: Master Toggle | Toggle disables all | Both phase automations check `modo_ventilacion_nocturna == on` | ✅ COMPLIANT |
| R2: Night Opening | Notification fires | Phase 1 sends notify.send_message + actionable notify | ⚠️ PARTIAL — Miriam doesn't get actionable (see CRITICAL #2) |
| R2: Night Opening | "Ya he abierto" opens windows | choose block sets ventanas_abiertas on OPENED | ❌ PARTIAL — also sets skip_today due to indentation bug (see CRITICAL #1) |
| R2: Night Opening | Skip does nothing | Skip triggers skip_today (different behavior from "No ahora") | ⚠️ PARTIAL — functionally different from spec (silences for rest of day) |
| R2: Night Opening | Already open, no re-notify | Condition checks `ventanas_abiertas == off` | ✅ COMPLIANT |
| R3: Morning Closing | Notification fires | Phase 2 sends notify.send_message + actionable notify | ⚠️ PARTIAL — Miriam doesn't get actionable (see CRITICAL #2) |
| R3: Morning Closing | "Ya he cerrado" clears state | choose block sets ventanas_abiertas off on CLOSED | ✅ COMPLIANT |
| R3: Morning Closing | Already closed, no re-notify | Condition checks `ventanas_abiertas == on` | ✅ COMPLIANT |
| R4: Sensor Unavailability | Indoor sensor unavailable | Both phases have availability template check | ✅ COMPLIANT |
| R4: Sensor Unavailability | Outdoor sensor non-numeric | Both phases have availability template check | ✅ COMPLIANT |

**Compliance summary**: 5/10 fully compliant, 3 partial, 1 partially broken by bug, 1 functionally different

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|------------|--------|-------|
| TASK-001: 3 input_boolean helpers | ✅ Implemented | modo_ventilacion_nocturna, ventanas_abiertas, night_purge_skip_today all present under NIGHT PURGE section |
| TASK-002: Phase 1 automation (1768000000003) | ⚠️ Implemented with bugs | See CRITICAL issues below |
| TASK-003: Phase 2 automation (1768000000004) | ✅ Implemented | Clean, no structural issues |
| TASK-004: YAML syntax verification | ✅ Done | Validated via python3 yaml — both files valid, no duplicate IDs |
| Sensor references match | ✅ Valid | Both sensors used in existing automations (1768000000001, 1768000000000) |
| Entity references match | ✅ Valid | All input_booleans in automations match configuration.yaml |
| notify.mobile_app_miriam_iphone | ✅ Correct | Uses consistent pattern with ventilation automation |
| Messages in español ibérico (tú form) | ✅ Correct | "Abre", "Cierra" — imperative tú form throughout |

### Coherence (Design)

| Decision | Followed? | Notes |
|----------|-----------|-------|
| Actionable notification pattern (send + wait_for_trigger) | ✅ Yes | Follows termo gym pattern in both phases |
| Anti-spam: state checks only | ⚠️ Partial | Design said state checks only but implementation added skip_today |
| Both phones actionable | ❌ No | **CRITICAL**: Only Ale gets actions. Design explicitly chose "Both phones" and rejected "Ale only" |
| Automation IDs (1768000000003, 1768000000004) | ✅ Yes | Sequential IDs follow ventilation family convention |
| Sensor unavailability pattern | ✅ Yes | Matches pattern from 1768000000001 |
| Message wording | ⚠️ Partial | Similar but not exact match to design/spec wording |
| Phase 1 time window (21:00–07:00) | ❌ No | Implementation covers 21:00–00:00 only, spec says 21:00–07:00 |
| Phase 2 time window (07:00–21:00) | ❌ No | Implementation covers 07:00–10:00 only, spec says 07:00–21:00 |

### Issues Found

**CRITICAL**:

1. **Indentation bug in Phase 1 — `turn_on night_purge_skip_today` always executes**
   - **Location**: `ha-config/automations.yaml` lines 766-769
   - **Root cause**: `- action: input_boolean.turn_on` targeting `night_purge_skip_today` (line 767) is at indentation level 2, the SAME as `- choose:` (line 755), not inside the SKIP_TODAY condition's `sequence:` block.
   - **Effect**: `night_purge_skip_today` is turned on AFTER the `choose` block, ALWAYS:
     - If user taps "Ya he abierto" → ventanas_abiertas turns on ✅ BUT skip_today ALSO turns on ❌, defeating the purpose
     - If timeout occurs (15 min) → skip_today turns on ❌, silently skipping rest of night
     - If user taps "Ignorar por hoy" → skip_today turns on ✅ (but only this case is correct)
   - **Fix needed**: Move lines 767-769 inside the SKIP_TODAY condition's `sequence:` block, indented properly.

2. **Miriam receives informational-only notification, not actionable**
   - **Location**: `ha-config/automations.yaml` lines 722-742 (Phase 1) and lines 810-828 (Phase 2)
   - **Root cause**: Only `notify.mobile_app_alejandros_iphone` is sent with action buttons. Miriam only gets `notify.send_message` (informational, no buttons). Both phases have this issue.
   - **Spec says**: "Both phones receive actionable notification"
   - **Design says**: "Both phones get action buttons" — chosen; "Only Ale receives actions" — rejected
   - **Fix needed**: Add `notify.mobile_app_miriam_iphone` calls with action buttons in both phases.

**WARNING**:

3. **Phase 1 time window truncated (21:00–00:00 instead of 21:00–07:00)**
   - The spec and design define Phase 1 as running 21:00–07:00. Implementation only covers 21:00–00:00 (3 hourly windows). Between 00:00–07:00, no night purge notification will fire, even if conditions are met.

4. **Phase 2 time window truncated (07:00–10:00 instead of 07:00–21:00)**
   - The spec and design define Phase 2 as running 07:00–21:00. Implementation only covers 07:00–10:00 (3 hourly windows). After 10:00, no morning close notification will fire, even if outdoor ≥ indoor.

5. **`night_pup_rge_skip_today` has no auto-reset mechanism**
   - Design rejected auto-reset as "scope creep". But once set, it persists indefinitely. If a user taps "Ignorar por hoy" at 23:30, it won't reset at midnight — so it's still set tomorrow night. Requires manual intervention.

6. **Notification messages differ from spec wording**
   - Phase 1 spec: "Hace más fresco fuera que dentro. Abre las ventanas para ventilar la casa."
   - Phase 1 impl: "Abre las ventanas. Está más fresco fuera que dentro y es buena hora para ventilar la casa."
   - Phase 2 spec: "Ya está más caliente fuera que dentro. Cierra las ventanas para mantener el fresco."
   - Phase 2 impl: "Cierra las ventanas. Ya está más caliente fuera que dentro. Es hora de mantener el fresco."
   - Same meaning, still español ibérico tú form, but not an exact match.

**SUGGESTION**:

7. **Add time-based auto-reset for `night_purge_skip_today`**
   - A simple automation that resets `night_purge_skip_today` to `off` at 21:00 each day would make the "Skip today" feature work as users naturally expect.

8. **Consider adding `notify.mobile_app_miriam_iphone` with action buttons**
   - If the design intent changes to "Ale actionable, Miriam info-only", update the design doc to reflect this and ensure it's intentional. Currently contradicts spec.

9. **Align message wording with spec** (minor)
   - Trivial change if spec accuracy matters.

### Verdict

**FAIL** — 2 CRITICAL issues prevent correct behavior

The Phase 1 indentation bug (CRITICAL #1) causes `night_purge_skip_today` to be set in ALL scenarios, including when the user opens windows or doesn't respond within 15 minutes — both defeating the intended behavior. Miriam not receiving actionable notifications (CRITICAL #2) directly contradicts the spec requirement and design decision. Both issues need resolution before deployment.
