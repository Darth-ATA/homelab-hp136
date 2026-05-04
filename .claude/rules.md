# Project Rules for AI Agents

## SSH Access to Proxmox

When connecting to Proxmox host via SSH, always use the pre-configured SSH key:

```bash
ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@192.168.1.134 "<command>"
```

**Proxmox Host Details:**
- Host: `192.168.1.134`
- User: `root`
- SSH Key: `~/.ssh/homelab_key`
- Node name: `prxhp136`

**Common Operations:**
- LXC configs: `/etc/pve/lxc/<ID>.conf`
- VM configs: `/etc/pve/qemu-server/<ID>.conf`
- Restart LXC: `pct stop <ID> && pct start <ID>`
- Restart VM: `qm stop <ID> && qm start <ID>`
