# Proposal: Soularr Integration

## Intent

Lidarr has poor coverage on public torrent trackers for music. Without Usenet, most wanted albums never get hits. Soularr bridges Lidarr to Soulseek P2P via slskd, giving Lidarr access to the largest music-sharing network available.

## Scope

### In Scope
- Deploy slskd container (Soulseek daemon) via Arcane on LXC 101
- Deploy soularr container (automation script) via Arcane on LXC 101
- Shared `/data/soulseek/` download directory under the existing single `/data` mount
- Arcane project configs for both containers in `/root/docker/arcane/data/projects/`
- Reference compose files in `docker/slskd/` and `docker/soularr/`
- Update `docker/README.md` with new services and storage layout
- Router port forward for slskd P2P (50300)

### Out of Scope
- Changing Lidarr's download client setup (Deluge stays for torrents, Soulseek is additional)
- VPN for Soulseek traffic
- High-availability or multi-instance for slskd/soularr
- Nginx Proxy Manager proxy hosts (deferred — not needed initially)
- Router port forwarding (slskd works in outbound-only mode; fewer peers but fully functional)

## Capabilities

### New Capabilities
- `soularr-integration`: Connect Lidarr to Soulseek via slskd for music acquisition unavailable on public trackets — covers container deployment, shared storage, auth config, and import workflow

### Modified Capabilities
- None

## Approach

Deploy two new containers under Arcane, matching the existing `arrsuite` conventions (PUID/PGID 1000, TZ Europe/Madrid, `/data:/data` mount):

1. **slskd**: Soulseek daemon. Config at `/root/docker/slskd/`, web UI on 5030, P2P on 50300. API key generated at startup for soularr auth.
2. **soularr**: Python script polling Lidarr wanted list every 5 min. Config.ini with both API keys. Web UI on 8265. Uses `use_selected_lidarr_release = True` for best results.

Both write to `/data/soulseek/` — hardlink-friendly under the single `/data` mount shared with Lidarr. Lidarr root folder stays `/data/media/music`, import works via the existing flow.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `docker/slskd/compose.yml` | New | slskd container definition |
| `docker/soularr/compose.yml` | New | soularr container definition |
| `docker/README.md` | Modified | Add slskd/soularr to stack table, storage layout |
| LXC 101 filesystem | Modified | New dirs: `/root/docker/slskd/`, `/root/docker/soularr/`, `/data/soulseek/` |
| Router | Not modified | Port forward explicitly excluded; slskd uses outbound-only mode |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Soulseek P2P blocked by ISP | Low | Soularr works with outbound-only slskd — fewer peers but fully functional |
| slskd API key rotation breaks soularr | Low | Both in same config.ini, documented in README |
| `/data/soulseek/` permission mismatch | Low | Both containers use PUID/PGID 1000, same as Lidarr |

## Rollback Plan

1. Remove slskd and soularr projects from Arcane (Arcane stops containers)
2. Delete `/root/docker/slskd/`, `/root/docker/soularr/`, `/data/soulseek/`
3. ~~Remove router port forward for 50300~~ (not applicable — out of scope)
4. Revert `docker/README.md` changes

## Dependencies

- slskd image: `ghcr.io/slskd/slskd:latest` (public GHCR)
- soularr image: `mrusse08/soularr:latest` (public Docker Hub)
- Lidarr API key (existing, retrieved from Lidarr settings)
- Port 50300 available on LXC 101 firewall

## Success Criteria

- [ ] slskd web UI reachable at http://192.168.1.142:5030
- [ ] soularr web UI reachable at http://192.168.1.142:8265
- [ ] Lidarr wanted album appears in soularr search queue
- [ ] Download completes in `/data/soulseek/` and Lidarr auto-imports to `/data/media/music/`
- [ ] Both containers restart cleanly on LXC reboot
