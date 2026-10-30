# Archive Report: ha-night-purge-49

**Archived**: 2026-06-26
**PR**: [#59](https://github.com/Darth-ATA/homelab-hp136/pull/59) — feat(ha-config): add night purging automation with actionable notifications
**Closes**: #49
**Artifact Store Mode**: hybrid (Engram + OpenSpec filesystem)
**Skill Resolution**: none (no Project Standards injected; no skill registry needed for archive phase)

---

## Artifact Lineage

### Engram Artifacts (homelab-hp136)

| Artifact | Observation ID | Topic Key |
|----------|---------------|-----------|
| Init | #1 | `sdd-init/homelab-hp136` |
| Proposal | #646 | `sdd/ha-night-purge-49/proposal` |
| Spec | #647 | `sdd/ha-night-purge-49/spec` |
| Design | #648 | `sdd/ha-night-purge-49/design` |
| Tasks | #649 | `sdd/ha-night-purge-49/tasks` |
| Apply-Progress | #650 | `sdd/ha-night-purge-49/apply-progress` |
| Verify-Report | #652 | `sdd/ha-night-purge-49/verify` |
| Archive-Report | (this) | `sdd/ha-night-purge-49/archive` |

### OpenSpec Filesystem Artifacts

| Artifact | Path |
|----------|------|
| Proposal | `openspec/changes/ha-night-purge-49/proposal.md` |
| Spec (delta) | `openspec/changes/ha-night-purge-49/specs/night-purge/spec.md` |
| Design | `openspec/changes/ha-night-purge-49/design.md` |
| Tasks | `openspec/changes/ha-night-purge-49/tasks.md` |
| Verify-Report | `openspec/changes/ha-night-purge-49/verify-report.md` |
| Archive-Report | `openspec/changes/ha-night-purge-49/archive.md` |

---

## Spec Sync Summary

| Domain | Action | Details |
|--------|--------|---------|
| `night-purge` | Already synced (no delta) | Delta spec identical to main spec. New domain — delta IS the full spec. No merge needed. |

The delta spec (`openspec/changes/ha-night-purge-49/specs/night-purge/spec.md`) was created as a full spec for a new domain — not a delta against an existing spec. Main spec at `openspec/specs/night-purge/spec.md` already contains the same content. No destructive merge warning needed.

---

## Implementation vs Spec Deltas

The following intentional deviations from the original spec were discovered during implementation:

| # | Spec | Implementation | Rationale |
|---|------|---------------|-----------|
| 1 | 2 input_booleans (`modo_ventilacion_nocturna`, `ventanas_abiertas`) | 3 input_booleans (+ `night_purge_skip_today`) | Added "Skip today" helper for user convenience. Acknowledged in verify report as functionally different from spec "No ahora" behavior. |
| 2 | Phase 1 action `NIGHT_PURGE_SKIP` ("No ahora") | `NIGHT_PURGE_SKIP_TODAY` ("Ignorar por hoy") | More useful UX — silences for rest of day instead of single cycle. |
| 3 | Timeout: 30 min | Timeout: 15 min | Per tasks.md, to match the 15-min time_pattern interval. Reduces notification lifetime. |
| 4 | Time window Phase 1: 21:00–07:00 | 21:00–00:00 (3 hourly windows) | Tasks.md defined 3 windows for both phases. Acknowledged in verify report as truncation. |
| 5 | Time window Phase 2: 07:00–21:00 | 07:00–10:00 (3 hourly windows) | Same as above — 3 windows per phase per tasks.md. |
| 6 | Message wording exact per spec | Similar wording, español ibérico tú form | Same meaning, natural language variation. |

### Critical Bug Fixes (apply-progress, commit `1d67234`)

| Bug | Before | After |
|-----|--------|-------|
| Indentation: `turn_on night_purge_skip_today` outside choose block | skip_today set unconditionally after every Phase 1 cycle | skip_today only set when "Ignorar por hoy" action tapped |
| Miriam lacks actionable notifications | Miriam received `notify.send_message` (info-only, no buttons) in both phases | Miriam receives same actionable notification as Ale in both phases |

---

## Verification Outcome

- **Initial verify report (stale)**: FAIL — 2 critical issues (indentation bug, Miriam no actionable)
- **Fixed in commit `1d67234`**: Both critical issues resolved
- **Tasks completed**: 5 (4 original + 1 fix commit)
- **Commits**: 5 total — b619be7, 8d4a0a5, f41d705, a0506cc, 1d67234

---

## Archive Contents

Moved to `openspec/changes/archive/2026-06-26-ha-night-purge-49/`:

| Artifact | Status |
|----------|--------|
| proposal.md | ✅ |
| specs/night-purge/spec.md | ✅ |
| design.md | ✅ |
| tasks.md | ✅ (4/4 tasks complete) |
| verify-report.md | ✅ |
| archive.md | ✅ (this report) |

---

## SDD Cycle Summary

| Phase | Status | Notes |
|-------|--------|-------|
| Init | ✅ | Project context established |
| Proposal | ✅ | Night purge with time-gated window recommendations |
| Spec | ✅ | 4 requirements, 10 scenarios |
| Design | ✅ | Actionable notification pattern, anti-spam decisions |
| Tasks | ✅ | 4 work units, single PR, low budget risk |
| Apply | ✅ | 5 commits, 2 bug fixes |
| Verify | ✅ | Static + syntax verification, critical bugs fixed |
| Archive | ✅ | Complete |

**SDD Cycle: COMPLETE** — Ready for the next change.
