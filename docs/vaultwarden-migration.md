# Vaultwarden Migration: Docker to Dedicated LXC

**Date**: 2026-06-22
**Migrated by**: SDD change `vaultwarden-dedicated-lxc`
**PR**: [#42](https://github.com/Darth-ATA/homelab-hp136/pull/42)

## Why

Vaultwarden was co-located in LXC 101 (Docker) alongside Deluge, \*Arr, and other services. A compromise of any container or application in that LXC could expose the password manager database. Dedicated LXC 104 isolates vaultwarden with its own kernel, network, and resource pool.

## Architecture

| Item | Old | New |
|------|-----|-----|
| Location | LXC 101 (Docker container) | LXC 104 (dedicated) |
| OS | Alpine (via Docker image) | Alpine 3.23 (LXC template) |
| CPU | Shared (2 cores) | 1 dedicated core |
| RAM | Shared (6GB pool) | 512MB dedicated |
| Disk | 150GB shared (ZFS) | 4GB dedicated (ZFS) |
| IP | 192.168.1.142 (LXC) | 192.168.1.144 (static) |
| Port | 8080 (Docker mapped from 80) | 8000 (native) |
| TLS | Via NPM (https → http) | Via NPM (https → http) |
| Domain | vw.hp136.duckdns.org | vw.hp136.duckdns.org (unchanged) |

## Migration Steps

### 1. Create LXC 104

```bash
# Run community script on Proxmox
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/alpine-vaultwarden.sh)"

# After creation, adjust resources
pct resize 104 rootfs 4G
pct set 104 -memory 512

# Set static IP
pct set 104 -net0 name=eth0,bridge=vmbr0,firewall=1,gw=192.168.1.1,ip=192.168.1.144/24

# Reboot to apply IP
pct reboot 104
```

### 2. Migrate Data

```bash
# Stop vaultwarden on both sides
pct exec 101 -- docker stop vaultwarden
pct exec 104 -- rc-service vaultwarden stop

# Tar data from old LXC
pct exec 101 -- tar czf /tmp/vaultwarden-data.tar.gz -C /root/docker/arcane/data/projects/vaultwarden/data .

# Copy to new LXC
pct push 104 /tmp/vaultwarden-data.tar.gz /tmp/vaultwarden-data.tar.gz

# Extract on new LXC
pct exec 104 -- tar xzf /tmp/vaultwarden-data.tar.gz -C /var/lib/vaultwarden/

# Fix ownership
pct exec 104 -- chown -R vaultwarden:vaultwarden /var/lib/vaultwarden/

# Start vaultwarden on new LXC
pct exec 104 -- rc-service vaultwarden start
```

### 3. Fix TLS (if needed)

The community script enables TLS by default (self-signed on port 8000). NPM cannot verify self-signed upstream certs:

```bash
# Disable TLS in vaultwarden config
pct exec 104 -- sed -i 's/^ROCKET_TLS=.*//' /etc/conf.d/vaultwarden
pct exec 104 -- rc-service vaultwarden restart
```

NPM proxy must target `http://192.168.1.144:8000` (not https).

### 4. Update NPM Proxy

1. In NPM web UI (http://192.168.1.142:81), edit the vaultwarden proxy host
2. Change scheme to `http`
3. Change forward port to `8000`
4. Save

If NPM doesn't regenerate the nginx config:

```bash
# Get the proxy host ID from NPM DB, then edit directly
pct exec 101 -- cat /root/docker/arcane/data/projects/npm/data/proxy_host/<id>.conf

# Edit and reload
pct exec 101 -- nginx -s reload
```

### 5. Terraform IaC

Import and verify:

```bash
terraform import proxmox_virtual_environment_container.vaultwarden prxhp136/104
terraform plan    # Verify expected changes
terraform apply   # Apply firewall, backup, and container config
```

### 6. Cleanup Old

```bash
# Remove Arcane project (if not already done)
pct exec 101 -- rm -rf /root/docker/arcane/data/projects/vaultwarden
```

## Rollback

If something goes wrong:

1. Revert NPM proxy target to `http://192.168.1.142:8080`
2. Start vaultwarden Docker container on LXC 101: `docker start vaultwarden`
3. Remove LXC 104: `pct stop 104 && pct destroy 104`
4. Revert Terraform changes via `git revert`

The old data on LXC 101 was preserved until cleanup step 6.

## Gotchas

- **Alpine LXC type**: Must set `operating_system { type = "alpine" }` in Terraform, not the default `ubuntu`.
- **Port**: Alpine vaultwarden runs on port **8000** (not 80 like the Docker image).
- **TLS**: Community script enables self-signed TLS. NPM needs HTTP upstream, so TLS must be disabled in `/etc/conf.d/vaultwarden`.
- **Unprivileged**: Alpine unprivileged containers need `features { keyctl = true }` and `nesting = true` for vaultwarden.
- **Volume mount**: Alpine vaultwarden stores data at `/var/lib/vaultwarden/` by default (not `/data` like Docker).
- **NPM config drift**: NPM's nginx config is generated from its DB. Direct file edits work but may be overwritten by NPM on restart.

## Verification

```bash
# Service responds
curl -sI https://vw.hp136.duckdns.org | head -1
# Expected: HTTP/2 200

# Terraform state is clean
terraform plan
# Expected: no changes
```
