# Homelab Terraform

Configuración de Terraform para gestionar contenedores LXC en Proxmox.

## Requisitos

- Terraform >= 1.0
- Proxmox VE con API habilitada
- SSH configurado con llaves (para importación manual)

## Estructura

```
homelab-terraform/
├── main.tf                    # Provider y configuración base
├── variables.tf               # Definición de variables
├── nuevo-contenedor-ejemplo.tf  # Ejemplo para nuevos contenedores
├── .gitignore                # Archivos ignorados
└── README.md
```

## Configuración

1. **Crear archivo `terraform.tfvars`** (no se sube a Git):
   ```bash
   cat > terraform.tfvars << 'EOL'
   proxmox_api_token = "root@pam!terraform-token-root=TU_TOKEN_AQUI"
   proxmox_endpoint = "https://192.168.1.134:8006/api2/json"
   EOL
   ```

2. **Inicializar Terraform:**
   ```bash
   terraform init
   ```

3. **Crear un nuevo contenedor:**
   - Editar `nuevo-contenedor-ejemplo.tf` con el ID, nombre y configuración deseada
   - Asegurarse de usar un `vm_id` que no esté en uso
   ```bash
   terraform plan
   terraform apply
   ```

## Contenedores Existentes (No gestionados por Terraform)

Los siguientes contenedores fueron creados manualmente y **NO** están bajo gestión de Terraform para evitar reemplazos no deseados:

| ID  | Nombre    | Descripción |
|-----|-----------|-------------|
| 101 | docker    | Contenedor con Docker (2 cores, 4GB RAM) |
| 102 | tailscale  | Contenedor con Tailscale (1 core, 512MB RAM) |
| 103 | adguard   | Contenedor con AdGuard (1 core, 512MB RAM) |
| 105 | debian-test | Contenedor de prueba (1 core, 512MB RAM) |

## Importar Contenedores (Avanzado)

Si deseas importar un contenedor existente (requiere downtime):

```bash
# Importar
terraform import proxmox_virtual_environment_container.nombre prxhp136/ID

# Verificar
terraform show
```

**Advertencia:** El provider `bpg/proxmox` tiene bugs conocidos con importación que pueden causar reemplazos no deseados. Usar con precaución.

## Recursos

- [Documentación del Provider bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/index.html)
