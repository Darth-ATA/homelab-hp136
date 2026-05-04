# homelab-hp136

Terraform configuration for managing LXC containers on Proxmox VE using the `bpg/proxmox` provider.

## Overview

This project provides Infrastructure as Code (IaC) for a Proxmox homelab environment. It allows you to create, modify, and manage LXC containers programmatically instead of using the Proxmox web interface interactively.

**Note:** This setup uses Terraform mainly for **creating new containers**. Due to known bugs in the `bpg/proxmox` provider with imports (issues #1406, #1998), existing containers are documented but not managed by Terraform to avoid unintended replacements.

## Project Structure

```
homelab-terraform/
├── main.tf                      # Provider and base configuration
├── variables.tf                 # Variable definitions
├── new-container-example.tf     # Template for new containers
├── .gitignore                  # Protect sensitive data
└── README.md
```

## Prerequisites

- Terraform >= 1.0
- Proxmox VE with API enabled
- SSH access configured with keys (for manual imports if needed)
- Existing LXC templates on Proxmox (e.g., Debian 13)

## Setup

### 1. Create `terraform.tfvars` (not committed to Git):

```bash
cat > terraform.tfvars << 'EOL'
proxmox_api_token = "root@pam!terraform-token-root=YOUR_TOKEN_HERE"
proxmox_endpoint = "https://192.168.1.134:8006/api2/json"
EOL
```

### 2. Initialize Terraform:

```bash
terraform init
```

### 3. Create a new container:

- Copy `new-container-example.tf` to a new file or edit it
- Update `vm_id` (use an unused ID), `hostname`, and configuration
- Run:
  ```bash
  terraform plan
  terraform apply
  ```

## Existing Containers (Not managed by Terraform)

The following containers were created manually and are **NOT** under Terraform management to prevent unintended replacements due to provider bugs:

| ID  | Name      | Description |
|-----|-----------|-------------|
| 101 | docker    | Container with Docker (2 cores, 4GB RAM) |
| 102 | tailscale  | Container with Tailscale (1 core, 512MB RAM) |
| 103 | adguard   | Container with AdGuard (1 core, 512MB RAM) |
| 105 | debian-test | Test container (1 core, 512MB RAM) |

## Importing Containers (Advanced)

If you want to import an existing container (requires downtime):

```bash
# Import
terraform import proxmox_virtual_environment_container.name prxhp136/ID

# Verify
terraform show
```

**Warning:** The `bpg/proxmox` provider has known issues (#1406, #1998) that may cause forced replacements after import. Use with caution.

## Resources

- [bpg/proxmox Provider Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/index.html)

## Security

- API tokens and state files are excluded from Git via `.gitignore`
- Never commit `terraform.tfvars` or `.terraform/` directory
- Use sensitive variables for passwords and tokens
