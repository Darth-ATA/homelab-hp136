# Tasks: Vaultwarden Dedicated LXC

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~150-200 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: single-pr
400-line budget risk: Low

## Phase 1: LXC Creation & Data Migration

- [ ] 1.1 SSH to Proxmox and run community script to create LXC 104 (Debian 13, 1 core, 512MB, 8GB)
- [ ] 1.2 Set static IP `192.168.1.144/24` in LXC 104's `/etc/network/interfaces`, restart network
- [ ] 1.3 Pack Vaultwarden data from LXC 101 (`/root/docker/arcane/data/projects/vaultwarden/data`) via tar, copy to host, extract to LXC 104 (`/opt/vaultwarden/`)
- [ ] 1.4 Start vaultwarden service on LXC 104, verify HTTP 200 on port 80

## Phase 2: Infrastructure as Code

- [ ] 2.1 Add backup job for LXC 104 in `backup.tf` (daily 04:15, local storage, keep-daily=1 + keep-monthly=1)
- [ ] 2.2 Add `vaultwarden` security group in `firewall.tf` (HTTP 80, dest `192.168.1.144`, source `192.168.1.142`)
- [ ] 2.3 Add `vaultwarden` security group reference to `proxmox_virtual_environment_firewall_rules.cluster` in `firewall.tf`

## Phase 3: NPM Update & Verification

- [ ] 3.1 Update NPM proxy host `vw.hp136.duckdns.org` target from `192.168.1.142:8080` to `192.168.1.144:80`
- [ ] 3.2 Verify Vaultwarden at `vw.hp136.duckdns.org` — login, unlock, sync, confirm data intact
- [ ] 3.3 Run `terraform plan` to confirm no unexpected changes

## Phase 4: Documentation & Cleanup

- [ ] 4.1 Update `NETWORK.md` — add LXC 104 row in static IPs table, update Vaultwarden access entry
- [ ] 4.2 Update `docker/README.md` — remove Vaultwarden from services table, update URLs section
- [ ] 4.3 Update `README.md` — add LXC 104 to containers table, services table, and backup strategy table
- [ ] 4.4 Update `CLAUDE.md` — add LXC 104 row in container/VM IDs table
- [ ] 4.5 Delete `docker/vaultwarden/compose.yml`
- [ ] 4.6 Write migration doc `docs/vaultwarden-migration.md` with procedure + rollback steps
- [ ] 4.7 Decommission old Vaultwarden Docker container via Arcane web UI
- [ ] 4.8 Optionally: `terraform import proxmox_virtual_environment_container.vaultwarden prxhp136/104`
