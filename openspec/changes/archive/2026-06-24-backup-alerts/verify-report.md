# Verify Report: Backup Alerts

**Change**: backup-alerts
**Status**: partial
**Mode**: Standard (no Strict TDD)
**Date**: 2026-06-24

## Summary

Implementation is structurally complete with all 7 tasks signed off, but a state tracking bug in `check-backup-disk.sh` means Telegram cooldown is non-functional for warning/critical states — the user will get repeated alerts every 60 minutes instead of respecting the 30-minute cooldown. One design deviation (`mailnotification = "failure"` instead of `"never"`) is well-justified by provider constraints.

---

## Verification Results

### 1. backup.tf — PASS

| # | Check | Result |
|---|-------|--------|
| ✓ | `mailnotification = "failure"` on all 5 resources | ✅ All 5 present (home_assistant, tailscale, adguard, vaultwarden, jellyfin) |
| ✓ | No other changes to backup.tf | ✅ Git diff shows exactly +10 lines, only `mailnotification = "failure"` insertions + blank lines |
| ✓ | terraform fmt'd | ✅ `terraform fmt --check` exits 0 |

### 2. scripts/check-backup-status.sh — PASS

| # | Check | Result |
|---|-------|--------|
| ✓ | `set -Eeuo pipefail` at line 2 | ✅ Present at line 13 (after shebang + comment block — standard pattern) |
| ✓ | Sources `/root/.env` gracefully | ✅ `if [[ -f "/root/.env" ]]; then source "/root/.env"; fi` |
| ✓ | Reads `/var/log/pve/tasks/index` | ✅ `INDEX_FILE="/var/log/pve/tasks/index"` |
| ✓ | Filters vzdump with VMIDs 100-105 | ✅ awk filter: `$6 == "vzdump" && $7 ~ /^(100|101|102|103|104|105)$/` |
| ✓ | Hex timestamp conversion | ✅ `ts = ("0x" hex_ts) + 0` in awk |
| ✓ | Has `alert_via_telegram()` function | ✅ Lines 69-93 |
| ✓ | Has `read_state()`/`write_state()` with cooldown | ✅ Lines 50-65 (cooldown at line 80) |
| ✓ | Sends healthy/recovery Telegram messages | ✅ Lines 206-213 (recovery), lines 236-243 (failure) |
| ✓ | Exit 0 on healthy, 1 on failure | ✅ Line 219 (exit 0), line 250 (exit 1) |
| ✓ | `bash -n` passes | ✅ |

### 3. scripts/check-backup-disk.sh — PASS WITH WARNING

| # | Check | Result |
|---|-------|--------|
| ✓ | `set -Eeuo pipefail` at line 2 | ✅ Present at line 11 (after shebang + comment block — standard pattern) |
| ✓ | Sources `/root/.env` gracefully | ✅ `if [[ -f "/root/.env" ]]; then source "/root/.env"; fi` |
| ✓ | Monitors `/var/lib/vz/dump` | ✅ `BACKUP_STORAGE="/var/lib/vz/dump"` |
| ✓ | Warn 80%, critical 90%, configurable via args | ✅ Defaults at lines 19-20, `-w`/`-c` parsed via getopts |
| ✓ | Has `alert_via_telegram()` function | ✅ Lines 60-84 |
| ✓ | Has `read_state()`/`write_state()` with cooldown | ✅ Lines 41-56 (cooldown at line 71) |
| ✓ | Sends recovery Telegram when usage drops | ✅ Lines 219-227 |
| ✓ | Keeps email alert as secondary channel | ✅ Lines 184-185 (critical) and 207-208 (warning) |
| ✓ | Exit codes: 0=ok, 1=warning, 2=critical | ✅ Line 233 (exit 0), line 212 (exit 1), line 189 (exit 2) |
| ✓ | `bash -n` passes | ✅ |
| ⚠️ | Cooldown works for all states | ❌ **BUG**: Cooldown check at line 71 only matches `"unhealthy"` but the disk script uses states `"warning"` and `"critical"`. Cooldown is effectively bypassed for all disk alerts. |

### 4. .gitignore — PASS

| # | Check | Result |
|---|-------|--------|
| ✓ | Contains `/root/.env` | ✅ Line 30, with explanatory comment |

### 5. docs/backup-alerts.md — PASS

| # | Check | Result |
|---|-------|--------|
| ✓ | Covers .env creation | ✅ Section 1 |
| ✓ | Covers script deployment (scp) | ✅ Section 2 |
| ✓ | Covers cron entries (with verification) | ✅ Section 3, includes `run-parts --test` |
| ✓ | Covers manual verification steps | ✅ Section "Manual Verification" |
| ✓ | Covers rollback steps | ✅ Section "Rollback" |

---

### Design Deviation Assessment

| Deviation | Reason | Verdict |
|-----------|--------|---------|
| `mailnotification = "failure"` instead of `"never"` | `bpg/proxmox` provider only accepts `"always"` or `"failure"`. Design assumed `"never"` was valid. | ✅ **Justified** — `"failure"` silences success emails (the main annoyance) while keeping failure emails as a last-resort channel, which is consistent with the intent. |

---

## Issues

### CRITICAL
None.

### WARNING

1. **Cooldown bypassed for disk script warning/critical states**
   - **File**: `scripts/check-backup-disk.sh`, line 71
   - **What**: `alert_via_telegram()` checks `[[ "$PREVIOUS_STATE" == "unhealthy" ]]` to enforce cooldown, but the disk script uses states `"warning"` and `"critical"` — so the cooldown is never activated.
   - **Impact**: When disk usage is sustained at ≥80%, the user receives Telegram alerts on **every cron run** (every 60 min) instead of once per 30-minute cooldown window. 6+ alerts/day vs 1.
   - **Fix**: Change line 71 condition from `"unhealthy"` to `!= "healthy"` to cover all non-healthy states. This matches the recovery detection pattern already used at line 217.
   - **Note**: The same pattern in `check-router-dns.sh` works correctly because that script only uses `"healthy"`/`"unhealthy"` states. This bug was introduced when copying the pattern to a script with 3-state logic.

### SUGGESTION

1. **Threshold validation in disk script**
   - **File**: `scripts/check-backup-disk.sh`
   - **What**: No validation that `-w < -c`. If called as `-w 90 -c 80`, a usage of 85% would trigger the critical branch instead of warning.
   - **Impact**: Low — operator error only.
   - **Fix**: Add `if [[ "$WARN_THRESHOLD" -ge "$CRIT_THRESHOLD" ]]; then ...` after option parsing.

---

## Artifacts

| Type | Path/Key |
|------|----------|
| Proposal | `openspec/changes/backup-alerts/proposal.md` |
| Design | `openspec/changes/backup-alerts/design.md`, engram `sdd/backup-alerts/design` (#506) |
| Tasks | `openspec/changes/backup-alerts/tasks.md`, engram `sdd/backup-alerts/tasks` (#508) |
| Apply Progress | `openspec/changes/backup-alerts/apply-progress.md`, engram `sdd/backup-alerts/apply-progress` (#509) |
| Verify Report | `openspec/changes/backup-alerts/verify-report.md` (this), engram `sdd/backup-alerts/verify-report` |

## Next

Fix the cooldown bug in `check-backup-disk.sh` (line 71: `"unhealthy"` → `!= "healthy"`), then re-verify and proceed to `sdd-archive`.

## Risks

- **Cooldown bug**: Low blast radius (disk alerts are informative, not actionable-in-real-time), but annoying. Fix is trivial.
- **No test coverage**: Expected for IaC without test runner. Manual verification instructions in docs are adequate.

## Skill Resolution

injected
