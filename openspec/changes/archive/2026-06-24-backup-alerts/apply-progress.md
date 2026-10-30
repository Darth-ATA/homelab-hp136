# Apply Progress: Backup Alerts

**Status**: success
**Date**: 2026-06-24
**Mode**: Standard (no Strict TDD)

## Tasks Completed

### Phase 1: Infrastructure
- [x] **1.1** `backup.tf` — Added `mailnotification = "failure"` to all 5 resources (home_assistant, tailscale, adguard, vaultwarden, jellyfin). **Deviation**: Provider only accepts `"always"` or `"failure"`, not `"never"` as originally designed. Used `"failure"` — silences success emails while keeping failure notifications.
- [x] **1.2** `.gitignore` — Added `/root/.env` after existing env entries with comment.

### Phase 2: Monitoring Scripts
- [x] **2.1** `scripts/check-backup-status.sh` — Created PVE task log parser. Sources `/root/.env`, parses `/var/log/pve/tasks/index` with awk for vzdump entries in last 24h. Reuses `read_state`/`write_state`/`alert_via_telegram` pattern from `check-router-dns.sh`. State tracking with 30min cooldown. Logs to `/var/log/check-backup-status.log`.
- [x] **2.2** `scripts/check-backup-disk.sh` — Created disk usage monitor. Sources `/root/.env`, monitors `df /var/lib/vz/dump`, warns at 80%, critical at 90%. Sends Telegram (with state tracking) + email (always). Supports `-w` and `-c` threshold overrides.

### Phase 3: Documentation
- [x] **3.1** `docs/backup-alerts.md` — Setup docs covering .env creation, scp deployment, cron entries, manual verification, rollback, troubleshooting.

### Phase 4: Verification
- [x] **4.1** `terraform fmt` passed. `terraform plan` shows 2 resources updated (vaultwarden, jellyfin), 3 already matched from state. No resource replacement.
- [x] **4.2** `bash -n` syntax check passed for both scripts.

## Files Changed

| File | Action | What Was Done |
|------|--------|---------------|
| `backup.tf` | Modified | Added `mailnotification = "failure"` to 5 backup job resources |
| `.gitignore` | Modified | Added `/root/.env` entry |
| `scripts/check-backup-status.sh` | Created | PVE task log parser with Telegram alerts |
| `scripts/check-backup-disk.sh` | Created | Disk usage monitor with Telegram + email alerts |
| `docs/backup-alerts.md` | Created | Setup documentation |
| `openspec/changes/backup-alerts/tasks.md` | Modified | Marked all tasks as completed |

## Deviations from Design

1. **`mailnotification = "failure"` instead of `"never"`**: The `bpg/proxmox` provider only allows `"always"` or `"failure"`. The design specified `"never"` which is invalid. Changed to `"failure"` which stops success emails (the main annoyance) while keeping failure emails as a last-resort channel.

## Issues Found

None.

## Commits

1. `bea17bc` — `chore(terraform): disable email notifications on backup jobs`
2. `4f7726e` — `chore: ignore /root/.env`
3. `b00f0da` — `chore(scripts): add backup status monitor with Telegram alerts`
4. `d01a13a` — `chore(scripts): migrate disk monitor with Telegram alerts`
5. `6d62616` — `docs: add backup alerts setup documentation`

## Next

`Ready for sdd-verify`
