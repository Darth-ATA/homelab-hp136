# Tasks: Backup Alerts

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~438 |
| 400-line budget risk | Medium |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | backup.tf + .gitignore | Single PR | 6 lines — standalone infra change |
| 2 | Both scripts + docs | Single PR | ~432 lines — tightly coupled, scripts share .env pattern |

**Note**: Splitting into 2 PRs doesn't help — PR 2 would still carry 432 lines. Single PR is the right call. At 438 lines, this is 9% over budget — close enough that a focused commit flow and inline review comments are fine.

## Phase 1: Infrastructure (Terraform + Gitignore)

- [x] **1.1** `backup.tf` — Add `mailnotification = "failure"` to 5 resources: home_assistant, tailscale, adguard, vaultwarden, jellyfin. **Note**: docker-backup has no resource block in TF (managed manually) — no change needed there. **Deviation**: provider only accepts `"always"` or `"failure"`, not `"never"`. Used `"failure"`.
- [x] **1.2** `.gitignore` — Add `/root/.env` after existing env entries.

## Phase 2: Monitoring Scripts

- [x] **2.1** `scripts/check-backup-status.sh` — Create PVE task log parser. Sources `/root/.env`, parses `/var/log/pve/tasks/index` with awk for vzdump entries in last 24h, sends Telegram on failure + recovery. Reuses `read_state`/`write_state`/`alert_via_telegram` from `check-router-dns.sh` pattern. Logs to `/var/log/check-backup-status.log`.
- [x] **2.2** `scripts/check-backup-disk.sh` — Create disk usage monitor. Sources `/root/.env`, monitors `df /var/lib/vz/dump`, warns at 80%, critical at 90%. Sends Telegram (with state tracking) + email (always). Logs to `/var/log/check-backup-disk.log`.

## Phase 3: Documentation

- [x] **3.1** `docs/backup-alerts.md` — Setup docs: .env creation, script deployment (scp), cron entries, manual verification, rollback.

## Phase 4: Verification

- [x] **4.1** Run `terraform fmt` and `terraform plan` — verify `mailnotification = "failure"` is the only change with no resource replacement. Result: 2 resources updated (vaultwarden, jellyfin), 3 already matched from state.
- [x] **4.2** Validate scripts: `bash -n` syntax check passed for both scripts.

## Implementation Order

Phase 1 first (zero risk, enables the .env contract). Then Phase 2 scripts in parallel (no cross-dependency). Then Phase 3 docs. Phase 4 verification last.

## Key Decisions / Notes

- **docker-backup**: The design mentions a "commented-out resource" but backup.tf has no such block — docker is managed entirely manually. No change needed.
- **State tracking**: Both scripts copy `read_state`/`write_state`/`alert_via_telegram` verbatim from `check-router-dns.sh` (proven production pattern, active since May 2026).
- **Exit codes**: Status script exits 0 (healthy) or 1 (failure). Disk script exits 0 (ok), 1 (warning), 2 (critical).
