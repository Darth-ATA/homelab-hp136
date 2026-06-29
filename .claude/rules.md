# Project Rules for AI Agents

## Terraform-First Infrastructure

**ALL infrastructure and operational configuration MUST be managed via Terraform whenever possible.** This is not optional.

Use `null_resource` + `local-exec` with SSH (the established codebase pattern) for operations the `bpg/proxmox` provider doesn't natively support. Before ANY operational change, ask: "Can I express this as Terraform?" If yes, do it.

### Examples of Terraform-managed operations in this codebase:
- Mount points (media, jellyfin)
- Bluetooth USB passthrough  
- ZFS dataset tuning
- Cron jobs (docker prune)
- Docker prune scheduling

Only fall back to scripts or manual steps when Terraform is genuinely impractical.

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

## NPM (Nginx Proxy Manager) Configuration

### Important Documentation Rule

**After ANY change to NPM configuration (proxy hosts, SSL certificates, or settings), you MUST update:**

1. **`docs/npm-config.md`** - Main NPM configuration documentation
2. **`.claude/skills/npm-recovery/SKILL.md`** - NPM recovery skill documentation

This ensures both the user-facing documentation and the Claude skill knowledge are synchronized.

### When to Update

Update documentation when:
- Adding, removing, or modifying proxy hosts
- Changing SSL certificate configuration
- Updating access credentials
- Modifying target services or ports
- Changing the recovery script configurations

## Credentials and Secrets

**NEVER commit credentials to this repository.** This includes:

- API keys and tokens
- Passwords and secrets
- Private keys (SSH, GPG, etc.)
- Cloud provider credentials
- Database connection strings
- Any other sensitive data

### Pre-commit Protection

This project includes a pre-commit hook at `.githooks/pre-commit` that automatically blocks commits containing potential credentials. The hook scans files for common secret patterns and will reject the commit if detected.

### Handling Credentials Properly

- **Environment variables**: Store sensitive values in environment variables or `.env` files (which should be `.gitignore`'d)
- **Secrets managers**: Use tools like HashiCorp Vault, AWS Secrets Manager, or similar for production secrets
- **Terraform secrets**: Use `sops`, `vault`, or other secret management tools integrated with Terraform
- **.gitignore**: Ensure sensitive files are excluded from version control

### Bypassing the Hook (Emergency Only)

If you absolutely must bypass the pre-commit hook (extremely rare), use:

```bash
git commit --no-verify -m "Your commit message"
```

**Warning**: Only use `--no-verify` in true emergencies. Bypassing the hook risks exposing secrets. Always prefer fixing the underlying issue (removing secrets from commits) instead.