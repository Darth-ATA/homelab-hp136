# Tailscale DERP + Subnet Cutover Runbook

Operational runbook for the subnet migration (`192.168.1.0/24` → `10.10.10.0/24`).
Everything here is **manual runtime state** — it intentionally lives OUT of Terraform
(REQ-NET-005/REQ-NET-008). The broken PR #90 `null_resource` (`tailscale set
--force-prefer-derp=mad`) was removed in `fix(tailscale): remove invalid flag`
because the flag does not exist in Tailscale 1.94.2.

---

## 1. Ephemeral DERP override (runbook-only, never durable IaC)

`tailscale set --force-prefer-derp` does NOT exist (verified on Tailscale 1.94.2).
Use the ephemeral debug command instead — it only lasts until the next tailscaled
restart / session:

```bash
ssh -i ~/.ssh/homelab_key root@10.10.10.134 "pct exec 102 -- tailscale debug force-prefer-derp 19"
```

`19` = Madrid DERP region (see `tailscale debug derp-map` for current regions).

**Use case:** external WiFi blocks UDP 41641 (direct WireGuard handshakes), so
traffic must ride the HTTPS DERP relay. This is a per-session workaround, NOT a
config setting — do not persist it in Terraform.

To clear it:

```bash
ssh -i ~/.ssh/homelab_key root@10.10.10.134 "pct exec 102 -- tailscale debug force-prefer-derp 0"
```

## 2. Router window (EX520v, manual — exact values)

All EX520v changes are manual. Order matters (REQ-NET-009: **DNS is LAST**).

1. **LAN IP** → `10.10.10.1`
2. **DHCP pool** → `.150`–`.254` (keep static reservations out of the pool)
3. **slskd port forward** → `50300` → `10.10.10.142:50300`
4. **DoS blocked-MAC list** → clear (stale entries can lock out devices on the new LAN)
5. **DNS** → `10.10.10.2` — ONLY AFTER Apply B moved AdGuard (see §3)

Rollback (reverse order): restore LAN/DHCP/DNS/forward to `192.168.1.x`, re-block MACs.

## 3. Tailscale route flip (no remote-access gap)

Run on LXC 102 AFTER infra is on 10.10.10.x AND the new route is approved in the console:

1. Advertise BOTH routes (old + new):
   ```bash
   pct exec 102 -- tailscale set --advertise-routes=192.168.1.0/24,10.10.10.0/24
   ```
2. Approve `10.10.10.0/24` in the Tailscale admin console (Access Controls / routes).
3. Verify new route is accepted: `pct exec 102 -- tailscale status`
4. Advertise NEW route only:
   ```bash
   pct exec 102 -- tailscale set --advertise-routes=10.10.10.0/24
   ```
5. Verify: `pct exec 102 -- tailscale debug prefs` → `AdvertiseRoutes: ["10.10.10.0/24"]`
6. Original repro: connect from external default-config WiFi and confirm homelab access.

Rollback: re-advertise `192.168.1.0/24`, re-approve in console.

---

See [NETWORK.md](../NETWORK.md) for the allocation table and `docs/terraform-state-migration.md`
for the backend flip procedure.
