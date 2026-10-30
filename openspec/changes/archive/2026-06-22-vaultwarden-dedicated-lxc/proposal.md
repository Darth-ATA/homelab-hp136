# Proposal: Vaultwarden Dedicated LXC

## Intent

Vaultwarden co-located in LXC 101 with Deluge, \*Arr, Jellyfin creates security risk and resource contention. A dedicated LXC 104 isolates the password manager, reducing attack surface.

## Scope

### In Scope
- Create LXC 104 via community script (1c, 512MB, 8GB, IP 192.168.1.144)
- Set static IP post-creation
- Migrate data: Docker volume → `/opt/vaultwarden/`
- NPM proxy target: `192.168.1.142:8080` → `192.168.1.144:80`
- Backup job for LXC 104 in `backup.tf`
- Firewall rule (HTTP 80 from NPM) in `firewall.tf`
- Update docs (NETWORK.md, docker/README.md, README.md, CLAUDE.md)
- Verify instance at `vw.hp136.duckdns.org`
- Migration doc (`docs/vaultwarden-migration.md`)
- Decommission old Docker container via Arcane

### Out of Scope
- Moving NPM or other services from LXC 101
- VLANs or network segmentation
- Container firewall hardening beyond basic rules
- Docker in new LXC (community script uses systemd/Rust)

## Capabilities

No spec-level changes — pure infrastructure refactoring.

### New Capabilities
None

### Modified Capabilities
None

## Approach

1. Run community script on Proxmox host to create LXC 104
2. Set static IP `192.168.1.144/24` (fix `/etc/network/interfaces`)
3. Pack Vaultwarden data from LXC 101 (`/root/docker/arcane/.../vaultwarden/data`) → copy to host → extract to `/opt/vaultwarden/` in LXC 104
4. Start vaultwarden service, verify HTTP on port 80
5. Update NPM proxy `vw.hp136.duckdns.org` target to `192.168.1.144:80`
6. Test full flow: login, unlock, sync
7. Add backup job (04:15 daily) + firewall rule (HTTP 80 from 192.168.1.142)
8. Update docs + stop old container via Arcane
9. Optionally import LXC 104 into Terraform state

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `NETWORK.md` | Modified | Add LXC 104 row, update Vaultwarden entry |
| `docker/README.md` | Modified | Remove Vaultwarden from services table |
| `backup.tf` | Modified | Add LXC 104 backup (04:15 daily) |
| `firewall.tf` | Modified | Add `vaultwarden` security group (HTTP 80, dest 192.168.1.144) |
| `README.md` | Modified | Update container/services/backup tables |
| `CLAUDE.md` | Modified | Add LXC 104 entry |
| `docker/vaultwarden/compose.yml` | Removed | Decommission reference copy |
| `docs/vaultwarden-migration.md` | New | Migration procedure + rollback steps |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Script assigns DHCP instead of static | Med | Fix static IP post-creation |
| Data loss during migration | Low | Keep old container until verified; backup tar.gz on host |
| NPM proxy misconfig | Low | Test with `curl` before NPM UI update |
| DNS propagation delay | Low | ~30s window; acceptable |

## Rollback Plan

Old container stays running. If new instance fails: revert NPM target to `192.168.1.142:8080`. If that resolves: `pct destroy 104`. Data backup tar.gz on host as safety net.

## Dependencies

- Community script server availability (community-scripts.org)
- Debian 13 template on Proxmox
- Unused VMID 104

## Success Criteria

- [ ] `vw.hp136.duckdns.org` loads Vaultwarden login from new LXC
- [ ] All vault data intact (credentials, items, attachments)
- [ ] Backup job for LXC 104 configured and enabled
- [ ] Firewall allows HTTP from NPM (`192.168.1.142`) to LXC 104 (`192.168.1.144:80`)
- [ ] NETWORK.md and docker/README.md accurately reflect new state
- [ ] Old Vaultwarden Docker container stopped and removed from Arcane
- [ ] `terraform plan` shows no unexpected changes
