# Proposal: Backup Alerts

## Intent

Six Proxmox backup jobs, zero actionable alerts. Failures are invisible until restore time — data loss risk. Backup disk space fills silently (host script emails root only, no Telegram). The existing Telegram bot is already wired into other scripts but not backup monitoring.

## Scope

### In Scope
- Remove email alerts from TF: `mailnotification = "never"` on all 6 backup jobs
- Centralize tokens: `/root/.env` template, sourced by scripts, `.gitignore` entry
- New `scripts/check-backup-status.sh`: grep PVE task logs for backup failures → Telegram
- Migrate `scripts/check-backup-disk.sh` from host to repo; add Telegram alongside email
- Document cron setup in script headers

### Out of Scope
- Shared Telegram library (accepted duplication — scripts are standalone)
- PVE notification-system config (webhook/gotify — blocked by bpg/proxmox #2898)
- Terraform module refactoring
- Docker backup monitoring (CT 101 managed manually outside TF)
- Other monitoring (system health, service uptime)

## Capabilities

No spec-level behavior changes — this is config + ops improvement.

### New Capabilities
None

### Modified Capabilities
None

## Approach

1. **backup.tf**: Add `mailnotification = "never"` to each `proxmox_backup_job` resource. No other Terraform changes.
2. **/root/.env**: Format `TELEGRAM_BOT_TOKEN=xxx\nTELEGRAM_CHAT_ID=xxx`, `chmod 600`. Sourced at top of each script. Add to `.gitignore`.
3. **check-backup-status.sh**: Sources `.env`. Greps `/var/log/pve/tasks/{E,F}/` for completed backup tasks with non-zero exit codes matching configured VMIDs. Uses `alert_via_telegram()` pattern from existing scripts. State tracking with cooldown (same pattern as sonarr-healthcheck.sh).
4. **check-backup-disk.sh**: Copy existing host script to repo. Add `alert_via_telegram()` call on warn/critical thresholds, keep email as secondary. Source `/root/.env`.
5. **Cron**: Document entries in each script header. Scripts deployed to `/usr/local/bin/`.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `backup.tf` | Modified | Add `mailnotification = "never"` to all 6 jobs |
| `scripts/check-backup-status.sh` | New | PVE task log failure monitor |
| `scripts/check-backup-disk.sh` | New | Migrated from host + Telegram |
| `.gitignore` | Modified | Add `/root/.env` |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| PVE task log format changes across versions | Low | Extract VMID+status with flexible regex; test on current PVE 8.x format |
| `/root/.env` not deployed on new host | Low | Scripts skip Telegram silently if tokens missing; email still works on disk check |
| Token duplication across `/etc/cron.d/*` files | Low | Script sources `.env` first; existing cron env vars still work as fallback |

## Rollback Plan

1. **Terraform**: `git revert` the `mailnotification` commit → `terraform apply`
2. **Scripts**: `rm /usr/local/bin/check-backup-status.sh /usr/local/bin/check-backup-disk.sh` on host
3. **Tokens**: `rm /root/.env` on host
4. **Cron**: Remove associated lines from `/etc/cron.d/`
5. **Git**: Files revert cleanly with no migration needed — nothing is stateful beyond cron

## Dependencies

- Existing Telegram bot (already configured, tokens in `/etc/cron.d/*` files)
- `jq` on Proxmox host (for PVE task log parsing if JSON format is used)

## Success Criteria

- [ ] `terraform plan` shows `mailnotification` additions only — no resource replacement or drift
- [ ] `check-backup-status.sh` exits 0 on healthy backups; sends Telegram on simulated failure
- [ ] `check-backup-disk.sh` sends Telegram at warning/critical thresholds (test with `-w 1 -c 2`)
- [ ] `/root/.env` sourcing works: unset env vars → script skips Telegram gracefully
