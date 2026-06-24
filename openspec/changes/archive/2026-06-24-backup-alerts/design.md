# Design: Backup Alerts

## Technical Approach

Replace silent backup failures with actionable Telegram alerts. Four changes: (1) disable Proxmox email notifications on all backup jobs via Terraform, (2) centralize bot tokens in `/root/.env`, (3) new `check-backup-status.sh` that parses PVE task logs for failures, (4) migrate + extend `check-backup-disk.sh` from host to repo with Telegram alerting.

Mapping to proposal: all 5 approach items (backup.tf, .env, status check, disk check, docs) covered. Spec-level behavior unchanged — pure operational improvement.

## Architecture Decisions

### Decision: Task log parsing method

| Option | Tradeoff | Decision |
|--------|----------|----------|
| `/var/log/pve/tasks/{E,F}/` files | Empty files, no timestamps → can't filter by 24h window | ❌ |
| `/var/log/pve/tasks/index` | Structured, has timestamps, parses cleanly with awk | ✅ |

**Rationale**: The index file contains one line per task with a hex timestamp (field 5 by `:`) and status (last field). Converting hex to epoch gives a precise 24h window. The E/F directories are secondary verification.

### Decision: Script sourcing pattern

**Choice**: Each script sources `/root/.env` independently (bash `source /root/.env` with graceful fallback).
**Alternatives considered**: Shared library file — rejected by proposal as accepted duplication.
**Rationale**: Scripts are standalone cron jobs. A shared library adds dependency coupling with zero benefit for 2 scripts.

### Decision: State tracking reuse

**Choice**: Copy state tracking (`read_state`/`write_state`/cooldown) verbatim from `check-router-dns.sh`.
**Rationale**: Proven pattern, already tested in production since May 2026. Keeps scripts self-contained.

## Data Flow

```text
                    ┌──────────────────────────────────────┐
Proxmox Backup ──►  │  /var/log/pve/tasks/index            │
Jobs (03:00-04:30)  │  (vzdump entries with status + time) │
                    └──────────┬───────────────────────────┘
                               │ grep :vzdump: + VMID filter
                               ▼
                    ┌─────────────────────┐
                    │ check-backup-status  │────► Telegram (failure)
                    │ (cron 05:30 daily)  │────► /var/log/check-backup-status.log
                    └─────────────────────┘

                    ┌─────────────────────┐
Backup Storage ──►  │  df /var/lib/vz/dump │
                    └──────────┬──────────┘
                               │ usage >= 80%
                               ▼
                    ┌─────────────────────┐
                    │ check-backup-disk    │────► Telegram (warn/crit)
                    │ (cron */60 min)     │────► email root (existing)
                    │                     │────► /var/log/check-backup-disk.log
                    └─────────────────────┘
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `backup.tf` | Modify | Add `mailnotification = "never"` to all 5 active + 1 commented-out resource |
| `.gitignore` | Modify | Add `/root/.env` entry |
| `scripts/check-backup-status.sh` | Create | PVE task log failure monitor → Telegram |
| `scripts/check-backup-disk.sh` | Create | Migrated from host + Telegram alerts added |
| `docs/backup-alerts.md` | Create | Setup docs: .env format, cron deployment, verification |

## Interfaces / Contracts

### `/root/.env` format
```bash
# Telegram bot credentials — sourced by backup alert scripts
# Deploy: copy to /root/.env, chmod 600, verify with: source /root/.env && echo "$TELEGRAM_CHAT_ID"
TELEGRAM_BOT_TOKEN="<your-telegram-bot-token>"
TELEGRAM_CHAT_ID="<your-telegram-chat-id>"
```

### Telegram message templates

**check-backup-status** — Healthy:
```text
✅ *Backup Status — All OK*
All 6 backups completed successfully in the last 24h.
Host: prxhp136
Time: 2026-06-24 05:30:01
```

**check-backup-status** — Failure:
```text
🚨 *Backup Failure Detected*
Failed: 2 of 6 backups

• VM 101 (docker) — job errors
• VM 102 (tailscale) — job errors

Host: prxhp136
Window: 2026-06-23 03:00 – 2026-06-24 05:30
```

**check-backup-disk** — Warning:
```text
⚠️ *Backup Disk Warning*
Usage: 82% (45G / 55G)
Path: /var/lib/vz/dump
Host: prxhp136
Time: 2026-06-24 12:00:00
```

**check-backup-disk** — Critical:
```text
🚨 *Backup Disk CRITICAL*
Usage: 93% (51G / 55G)
Path: /var/lib/vz/dump
Host: prxhp136
Time: 2026-06-24 12:00:00
```

**check-backup-disk** — Recovery:
```text
✅ *Backup Disk Recovered*
Usage: now 75% (was above 80%)
Path: /var/lib/vz/dump
Host: prxhp136
Time: 2026-06-24 14:00:00
```

### State tracking contract (both scripts)
```bash
STATE_FILE="/var/tmp/check-backup-{status,disk}.state"
STATE_COOLDOWN=1800  # 30 minutes

# State file format:
PREVIOUS_STATE="healthy"    # or "unhealthy" / "warning" / "critical"
LAST_ALERT_TIME="1782200109"
```

### check-backup-status.sh pseudo-code
```bash
set -Eeuo pipefail
source /root/.env || log_warn "No /root/.env — Telegram alerts disabled"

VMIDS=(100 101 102 103 104 105)
declare -A VMID_NAMES=([100]="home-assistant" [101]="docker" [102]="tailscale"
                       [103]="adguard" [104]="vaultwarden" [105]="jellyfin")
INDEX_FILE="/var/log/pve/tasks/index"
CUTOFF=$(date -d '24 hours ago' +%s)

# read_state / write_state / alert_via_telegram — verbatim from check-router-dns.sh
# log_info / log_warn / log_error / log_ok — verbatim from check-router-dns.sh

# Parse index: awk -F: '$6=="vzdump" && $7 ~ /^(100|101|102|103|104|105)$/'
# Extract last field as status (last whitespace-separated token)
# Convert $5 (timestamp hex) to epoch: printf '%d' "0x${hex}"
# If epoch >= CUTOFF and status != "OK" → mark failure[$vmid]=status
# If no failures → exit 0 (send recovery msg if prev_state was unhealthy)
# If failures → compose alert, send Telegram, exit 1
```

### check-backup-disk.sh pseudo-code
```bash
set -Eeuo pipefail
source /root/.env || log_warn "No /root/.env — Telegram alerts disabled"

BACKUP_STORAGE="/var/lib/vz/dump"
WARN_THRESHOLD=80
CRIT_THRESHOLD=90

# read_state / write_state / alert_via_telegram — verbatim from check-router-dns.sh
# log_info / log_warn / log_error — verbatim from host script

# Parse options: -w PCT, -c PCT, -e EMAIL (same as host script)
# Check deps: df, awk, mail, curl
# Get usage: df "$BACKUP_STORAGE" | awk 'NR==2 {gsub(/%/,""); print $5}'
# Compare thresholds:
#   >= CRIT → Telegram (critical msg) + email root, exit 2
#   >= WARN → Telegram (warning msg) + email root, exit 1
#   < WARN  → if previous state was warn/crit → send recovery Telegram, exit 0
# Telegram alerts use state tracking; email alerts fire every time (existing behavior)
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | `backup.tf` | `terraform plan` — verify `mailnotification = "never"` appears with no other changes |
| Integration | `check-backup-status.sh` | Simulate with `-w 1 -c 2` args, verify exit codes, inspect log |
| Integration | `check-backup-disk.sh` | Test with `-w 1 -c 2` thresholds (always triggers), verify Telegram + email |
| E2E | Token sourcing | Run with/without `/root/.env`, verify Telegram skips gracefully |
| E2E | State tracking | Force state file, verify cooldown prevents duplicate alerts |

## Migration / Rollout

1. **Terraform**: `terraform apply` — adds `mailnotification = "never"` to all jobs, no resource replacement
2. **Manual**: Create `/root/.env` on Proxmox host, `chmod 600`
3. **Deploy scripts**: Copy `check-backup-status.sh` and `check-backup-disk.sh` to `/usr/local/bin/`
4. **Cron**: Add to `/etc/cron.d/`:
   - `30 5 * * * root /usr/local/bin/check-backup-status.sh` (after 04:30 backup window)
   - Existing `*/60 * * * * root /usr/local/bin/check-backup-disk.sh -w 80 -c 90` (update in place)
5. **Verify**: Manual run of both scripts, inspect `/var/log/` outputs

## Open Questions

None — all decisions resolved against live host data.

## Cron Schedule Recommendations

| Script | Schedule | Rationale |
|--------|----------|-----------|
| `check-backup-status.sh` | `30 5 * * *` | 05:30 daily — 1h after last backup (jellyfin at 04:30) |
| `check-backup-disk.sh` | `*/60 * * * *` | Every 60 min — existing schedule, keep unchanged |

Note: Remove the `* / * 0 * * *` old cron line from `/etc/cron.d/check-backup-disk` if it exists (current line uses `*/60` which is valid on Linux, but invalid on BSD — verify syntax with `run-parts --test`).

## Deployment Instructions

See `docs/backup-alerts.md` (created in task phase) for:
1. `.env` creation and verification
2. Script deployment (`scp` commands)
3. Cron setup
4. Manual test procedure
5. Rollback steps
