# Tasks: Soularr Integration

Bridge Lidarr to Soulseek P2P via slskd for music unavailable on public torrent trackers. Two new Arcane containers on LXC 101 with shared `/data/soulseek/` download storage.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~250 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

```
Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low
```

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | All repo files + deployment + verification | PR 1 | Single PR — under 400 lines |

## Phase 1: Reference Configuration Files (Repo)

- [ ] 1.1 Create `docker/slskd/compose.yml` with slskd container (user 1000:1000, env vars, ports 5030/50300, volumes, soularrnet network)
- [ ] 1.2 Create `docker/slskd/slskd.yml` with Soulseek credentials placeholders, download dirs, web auth config, retention settings
- [ ] 1.3 Create `docker/soularr/compose.yml` with soularr container (user 1000:1000, env vars, port 8265, volumes, soularrnet network)
- [ ] 1.4 Create `docker/soularr/config.ini` with Lidarr/slskd API key placeholders, release/search/download/logging sections

## Phase 2: LXC 101 Directory Setup

- [ ] 2.1 SSH via Proxmox host and create dirs: `/root/docker/slskd/config`, `/root/docker/soularr/config`, `/data/soulseek/{incomplete,downloads}`
- [ ] 2.2 Chown all new dirs to 1000:1000

## Phase 3: Configuration & Arcane Deployment

- [ ] 3.1 Write `slskd.yml` to `/root/docker/slskd/config/slskd.yml` with Soulseek username/password placeholders
- [ ] 3.2 Write `config.ini` to `/root/docker/soularr/config/config.ini` with API key placeholders
- [ ] 3.3 Generate slskd API key (`openssl rand -hex 32`) and write `.env` for Arcane project
- [ ] 3.4 Create Arcane project compose files at `/root/docker/arcane/data/projects/slskd/compose.yaml` and `/root/docker/arcane/data/projects/soularr/compose.yaml`
- [ ] 3.5 Register and deploy both projects via Arcane API (`POST /api/projects`)

## Phase 4: Secret Injection

- [ ] 4.1 Replace `SLSKD_API_KEY_GOES_HERE` in config.ini with generated key
- [ ] 4.2 Ask user for Lidarr API key and inject into config.ini
- [ ] 4.3 Ask user for Soulseek credentials and inject into slskd.yml
- [ ] 4.4 Restart both containers via Arcane to pick up config changes

## Phase 5: Verification

- [ ] 5.1 Verify slskd web UI reachable at `http://192.168.1.142:5030` (HTTP 200)
- [ ] 5.2 Verify soularr web UI reachable at `http://192.168.1.142:8265` (HTTP 200)
- [ ] 5.3 Verify slskd API authenticates with key via `GET /api/v0/transfers`
- [ ] 5.4 Check slskd + soularr logs for errors (no tracebacks, connected to Lidarr)
- [ ] 5.5 Test restart resilience: `docker restart slskd soularr` → both healthy

## Phase 6: Documentation

- [ ] 6.1 Update `docker/README.md` — add slskd/soularr to service table, storage layout, service URLs
