# Firewall Hardening - Restrict management access and implement VLAN

## Description

Follow-up to #3 (Firewall Configuration). Now that the firewall is enabled with permissive policies, we need to tighten security by restricting access and implementing network segmentation.

## Current State

- ✅ Firewall enabled at cluster level (ACCEPT policies)
- ✅ Security groups created (mgmt, dns, web, homeassistant, tailscale)
- ✅ Cluster firewall rules applied
- ✅ Container-level firewall enabled on all LXC containers
- ✅ Home Assistant VM firewall options configured

## Proposed Changes

### 1. Restrict Management Access
- **SSH (port 22)**: Change from open to restricted to management IPs only
- **Proxmox UI (port 8006)**: Restrict to management IPs only
- Update `mgmt` security group rules to include `source` field with management IPs

### 2. Change Default Policies
- Change cluster `input_policy` from `ACCEPT` to `DROP`
- Ensure all necessary services have explicit ACCEPT rules
- Test connectivity after changes

### 3. Define Management IPs
Add to `terraform.tfvars` or update `variables.tf`:
```hcl
management_ips = ["192.168.1.X/32", "192.168.1.Y/32"]  # Specific device IPs
```

### 4. VLAN for IoT Devices (Home Assistant)
- Create VLAN for IoT devices (e.g., VLAN 10)
- Configure network bridge for VLAN in Proxmox
- Move Home Assistant (VM 100) to IoT VLAN
- Update firewall rules to allow necessary communication between VLANs

### 5. Review and Clean Up
- Audit all open ports - remove unnecessary ones
- Consider if Tailscale UDP 41641 rule is needed (relay-only mode?)
- Document any port changes

## Implementation Steps

1. Update `variables.tf` with `management_ips`
2. Modify `firewall.tf`:
   - Update `mgmt` security group with source restrictions
   - Change `proxmox_virtual_environment_cluster_firewall.cluster` input_policy to `DROP`
3. Create VLAN configuration (new file or extend existing)
4. Test all services after applying changes
5. Update README.md with new restrictions

## Priority

**High** - Security

## Acceptance Criteria

- [ ] SSH restricted to management IPs only
- [ ] Proxmox UI (8006) restricted to management IPs only
- [ ] Cluster `input_policy` changed to `DROP`
- [ ] All necessary services still accessible
- [ ] VLAN configured for IoT devices (optional)
- [ ] Home Assistant moved to IoT VLAN (optional)
- [ ] Changes documented in README
- [ ] Test connectivity - no service disruptions

## Notes

- Test thoroughly to avoid lockouts - ensure your management IP is correct
- Consider keeping SSH open from all sources temporarily during testing
- May need console access to fix lockouts
