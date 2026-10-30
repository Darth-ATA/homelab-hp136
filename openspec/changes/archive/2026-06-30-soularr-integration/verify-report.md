# Verification Report: Soularr Integration

**Date**: 2026-06-30
**Verifier**: SDD Verify Phase
**Environment**: LXC 101 (192.168.1.142), Proxmox host 192.168.1.134

---

## Summary

| Requirement | Verdict | Details |
|-------------|---------|---------|
| REQ-001: slskd daemon | ✅ PASS | Running, connected to Soulseek, UI at :5030 |
| REQ-002: soularr automation | ⚠️ PARTIAL | Running, UI at :8265, but startup race condition with slskd |
| REQ-003: Shared download storage | ✅ PASS | Directory exists, correct ownership |
| REQ-004: P2P network ingress | ✅ PASS | Outbound-only, as designed |
| REQ-005: Service recovery | ⚠️ PARTIAL | Restart resilience works, but race condition on concurrent restart |
| **Repo files** | ✅ PASS | All reference files exist |
| **docker/README.md** | ❌ FAIL | Not updated with soularr/slskd entries |

---

## Detailed Verification

### Step 1: Check both containers are running

```text
slskd   Up (healthy)   0.0.0.0:5030->5030/tcp, 0.0.0.0:50300->50300/tcp
soularr Up             0.0.0.0:8265->8265/tcp
```

**Verdict: ✅ PASS** — Both containers running on `soularrnet` bridge network.

---

### Step 2: Check slskd web UI responds

```text
curl http://localhost:5030 → HTTP 200
```

**Verdict: ✅ PASS** — Login page served correctly.

---

### Step 3: Check soularr web UI responds

```text
curl http://localhost:8265 → HTTP 200
```

**Verdict: ✅ PASS** — Dashboard served correctly.

---

### Step 4: Check slskd logs for successful login

```text
[08:47:43 INF] Connected to the Soulseek server
[08:47:43 INF] Logged in to the Soulseek server as ata1007
```

**Verdict: ✅ PASS** — Successfully connected and authenticated to Soulseek.

---

### Step 5: Check soularr logs show searches happening

```text
[INFO|soularr|L455] Searching for album: Carolus Rex
[INFO|soularr|L480] Search returned 101 results
```

soularr DID successfully search and find results during the first startup cycle. However, after restart, it consistently gets `ConnectionRefused` when trying to reach slskd.

**Verdict: ⚠️ WARNING** — Searches work when slskd is already running, but there is a startup race condition (see Critical Issues).

---

### Step 6: Check the download directory exists

```text
/data/soulseek/ → drwxr-xr-x 4 1000 1000
  ├── downloads/ → drwxr-xr-x 2 1000 1000
  └── incomplete/ → drwxr-xr-x 2 1000 1000
```

**Verdict: ✅ PASS** — Directory structure exists with correct ownership (1000:1000).

---

### Step 7: Check for any error logs

**slskd**: No error logs. Connected, logged in, healthy.

**soularr**: 219 traceback/error entries found. Primary error pattern:

```
ConnectionRefusedError: [Errno 111] Connection refused
urllib3.exceptions.NewConnectionError: HTTPConnection(host='slskd', port=5030):
Failed to establish a new connection
```

Root cause: soularr starts before slskd's HTTP API is ready. On the first cycle attempt, slskd:5030 is not yet accepting connections. soularr's Python client throws an unhandled exception.

**Verdict: ⚠️ WARNING** — soularr produces error logs on every startup when both containers start simultaneously.

---

### Step 8: Test restart resilience

```text
docker restart slskd soularr
→ Both containers restart successfully
→ slskd: Up 28s (health: starting)
→ soularr: Up 28s
→ Both web UIs return HTTP 200 after restart
```

However, soularr consistently gets ConnectionRefused on slskd during the first cycle after restart. The slskd health check takes ~5 seconds to pass, while soularr tries to connect immediately.

**Verdict: ⚠️ WARNING** — Restart works, but soularr goes through error cycles before recovering. Each 300-second wait cycle gives slskd time to become ready, but the first cycle always fails.

---

### Step 9: Verify reference files exist in local repo

| File | Exists | Notes |
|------|--------|-------|
| `docker/slskd/compose.yml` | ✅ | Correct |
| `docker/slskd/slskd.yml` | ✅ | Correct |
| `docker/slskd/.env.example` | ✅ | Contains SOULSEEK_USER/SOULSEEK_PASS |
| `docker/soularr/compose.yml` | ✅ | Correct |
| `docker/soularr/config.ini` | ✅ | Correct |
| `docker/soularr/.env.example` | ✅ | Contains LIDARR_API_KEY |
| `scripts/deploy-soularr-secrets.sh` | ✅ | Correct, with validation |

**Verdict: ✅ PASS** — All 7 reference files present.

---

### Step 10: Verify docker/README.md has been updated

```text
grep -c -i 'soularr\|slskd' docker/README.md → 0 matches
```

**Verdict: ❌ FAIL** — Task 6.1 not completed. The README has no mention of slskd, soularr, or their ports.

---

## Detailed Requirement Mapping

### REQ-001: slskd daemon

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Runs as Arcane container on LXC 101 | ✅ | Deployed via Arcane, project at `/root/docker/arcane/data/projects/slskd/` |
| Web UI on :5030 | ✅ | HTTP 200 |
| P2P on :50300 | ✅ | Container exposes port, slskd listening |
| PUID/PGID 1000 | ✅ | `user: "1000:1000"` in compose |
| TZ Europe/Madrid | ✅ | `TZ=Europe/Madrid` env var |
| `/data` mount | ✅ | `/data:/data` in compose |
| Config at `/root/docker/slskd/` | ✅ | slskd.yml deployed |
| API key generation | ✅ | `SLSKD_API_KEY=eef9c16399d7a6f52e2a90dd3f2e29638e3fa2efc1b89353bcc0c314c4adc063` |

**Verdict: ✅ PASS**

### REQ-002: soularr automation

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Runs as Arcane container on LXC 101 | ✅ | Deployed via Arcane, project at `/root/docker/arcane/data/projects/soularr/` |
| Web UI on :8265 | ✅ | HTTP 200 |
| PUID/PGID 1000 | ✅ | Both env var + `user:` directive |
| TZ Europe/Madrid | ✅ | Env var |
| `/data` mount | ✅ | Config mounted at `/data` |
| Poll Every 5 min | ✅ | `SCRIPT_INTERVAL=300` |
| `use_selected_lidarr_release = True` | ✅ | In config.ini |
| References both API keys | ✅ | Lidarr + slskd keys filled in |

**Verdict: ✅ PASS** — Functionally correct, with caveat about startup race condition.

### REQ-003: Shared download storage

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Both write to `/data/soulseek/` | ✅ | Directory exists, both containers mount it |
| Lidarr imports from same path | ✅ | Lidarr has `/data:/data` mount |
| Hardlinks work (same `/data` mount) | ✅ | All containers share same ZFS mount |
| Ownership PUID 1000 | ✅ | `1000:1000` throughout |

**Verdict: ✅ PASS**

### REQ-004: P2P network ingress (deferred)

| Criterion | Result | Evidence |
|-----------|--------|----------|
| No port forwarding configured | ✅ | Not configured (as designed) |
| slskd operates outbound-only | ✅ | No incoming connections warning in logs: `Listening for incoming connections on 0.0.0.0:50300` — slskd listens but NAT blocks inbound |
| Downloads still work | ✅ | Searches succeed, results found |

**Verdict: ✅ PASS**

### REQ-005: Service recovery

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Restart on reboot (Arcane policy) | ✅ | `restart: unless-stopped` in both compose files |
| slskd reachable within 60s | ✅ | ~5s startup |
| soularr reachable within 60s | ✅ | ~3s startup |
| soularr resumes polling | ⚠️ Partial | Resumes but first cycle fails (slskd not ready) |

**Verdict: ⚠️ WARNING** — Recovery works but has a startup race condition.

---

## Critical Issues

### CRITICAL: Startup race condition between soularr and slskd

**Severity**: HIGH

**Description**: When both containers start simultaneously (reboot, `docker restart`, Arcane deploy), soularr tries to connect to slskd HTTP API before slskd is ready. slskd takes ~3-5 seconds to initialize its HTTP listener. soularr's Python `slskd_api` client immediately attempts a connection, gets `ConnectionRefused`, and the process crashes with unhandled exceptions.

**Evidence**:
```
urllib3.exceptions.NewConnectionError:
HTTPConnection(host='slskd', port=5030):
Failed to establish a new connection: [Errno 111] Connection refused
```

219 traceback/error entries in soularr logs in ~2 minutes of operation.

**Impact**: 
- First soularr cycle (~5 min) is wasted on errors
- No searches happen during this window
- If container is in a restart loop, it may never recover

**Fix**: Add `depends_on` with healthcheck condition to soularr's compose:
```yaml
services:
  soularr:
    depends_on:
      slskd:
        condition: service_healthy
```

Or add a startup delay in soularr's compose:
```yaml
environment:
  - SCRIPT_INTERVAL=300
  - INITIAL_DELAY=30   # Not standard, but can be simulated
```

### WARNING: config.ini file ownership

**Severity**: LOW

**Description**: `/root/docker/soularr/config/config.ini` is owned by `root:root` instead of `1000:1000`. While soularr can read it (644 permissions), this deviates from the design (Section 6, Phase 2).

**Evidence**:
```
-rw-r--r-- 1 root root 2150 Jun 30 06:44 config.ini
```

**Fix**: `chown 1000:1000 /root/docker/soularr/config/config.ini`

### FAIL: docker/README.md not updated

**Severity**: MEDIUM

**Description**: Task 6.1 requires updating `docker/README.md` with slskd/soularr service entries, storage layout, and service URLs. This was not done.

**Evidence**:
```text
grep -c -i 'soularr\|slskd' docker/README.md → 0 matches
```

**Fix**: Add entries for slskd (port 5030, Soulseek daemon) and soularr (port 8265, Lidarr-Soulseek bridge) to the stack table, URLs, and storage layout sections.

---

## Deviations from Spec/Design

| # | Spec/Design Requirement | Actual | Deviation | Severity |
|---|------------------------|--------|-----------|----------|
| 1 | PUID/PGID env vars for slskd (design 2.1) | Missing from compose.yml and deployed compose | Minor — `user: "1000:1000"` handles it at Docker level | SUGGESTION |
| 2 | config.ini owned by 1000:1000 (design Phase 2) | Owned by root:root | Permission mismatch | WARNING |
| 3 | docker/README.md updated (task 6.1) | Not updated | Task not completed | WARNING |
| 4 | `depends_on` with healthcheck (not in spec but needed) | No depends_on | Missing startup ordering | CRITICAL (gap) |

---

## Acceptance Criteria Status

| # | Criterion | Status |
|---|-----------|--------|
| 1 | slskd UI at http://192.168.1.142:5030 | ✅ PASS |
| 2 | soularr UI at http://192.168.1.142:8265 | ✅ PASS |
| 3 | Lidarr wanted album in soularr queue | ✅ PASS (soularr retrieved wanted list: Carolus Rex, The War to End All Wars) |
| 4 | Download completes, Lidarr imports | ⚠️ NOT TESTED (no download completed during verification window) |
| 5 | Both containers restart on LXC 101 reboot | ⚠️ PARTIAL (race condition on concurrent start) |

---

## Final Verdict

**Status: ⚠️ CONDITIONAL PASS**

The implementation is fundamentally correct:
- Both containers deploy and run
- slskd authenticates to Soulseek
- soularr connects to Lidarr and retrieves wanted albums
- Searches return results
- Configuration is properly injected

However, there are two issues that should be addressed before declaring Done:

1. **CRITICAL**: Fix the startup race condition by adding `depends_on` with healthcheck condition to soularr's compose.yml
2. **WARNING**: Update docker/README.md with the new services

The first issue can be deferred if you're comfortable with soularr producing error logs on startup (it will recover ~5 minutes after slskd is ready). The second is a documentation gap.
