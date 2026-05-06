# Home Assistant Configuration as Code

This directory contains the Home Assistant configuration files that can be used to recover or recreate your Home Assistant instance.

## Structure

```
ha-config/
├── home_assitant-vm.tf       # Terraform config for HA VM
├── configuration.yaml          # Main HA configuration
├── automations.yaml          # Automations (incl. gym water heater notification)
├── scripts.yaml              # Scripts (empty)
├── scenes.yaml               # Scenes (empty)
├── blueprints/              # Blueprints
│   ├── automation/
│   │   └── homeassitant/
│   │       ├── motion_light.yaml
│   │       └── notify_leaving_zone.yaml
│   └── script/
│       └── homeassitant/
│           └── confirmable_notification.yaml
├── .storage/               # HA internal state (for recovery)
│   ├── core.config           # Core config (location, timezone, etc.)
│   ├── core.area_registry   # Area definitions
│   ├── core.config_entries   # Integration configurations
│   └── core.device_registry # Device registry
└── README.md               # This file
```

## Key Automation: Gym Water Heater

The `automations.yaml` includes an automation that:
- Triggers when you enter the gym zone (Dreamfit Moratalaz)
- Checks if water heater (termostato) is off
- Sends a notification asking if you want to turn it on
- Waits for response and acts accordingly

## Recovery Instructions

### Option 1: Full Recovery (using .storage files)

1. Deploy HAOS VM using Terraform:
   ```bash
   cd /Users/alejandrotorresaguilera/homelab-terraform
   terraform apply -target=proxmox_virtual_environment_vm.home_assitant
   ```

2. Wait for HA to boot, then copy config files to VM:
   ```bash
   # Via Proxmox host
   scp -r ha-config/* root@192.168.1.134:/mnt/pve/nfs/...
   # Or use guest exec to copy files
   ```

3. Restart Home Assistant

### Option 2: Fresh Setup

1. Deploy HAOS VM using Terraform
2. Complete onboarding via http://192.168.1.100:8123
3. Copy `configuration.yaml` and `automations.yaml` to HA
4. Manually configure integrations (Zigbee, Ring, Mobile Apps, etc.)

## Sensitive Data

The `.storage/core.config_entries` file has been sanitized:
- Replace `CHANGE_ME_HACS_TOKEN` with your HACS token
- Replace `CHANGE_ME_RING_PASSWORD` with your Ring password
- Mobile app secrets and push tokens are preserved (needed for notifications)

## Integrations Configured

- **Sun** - Sunrise/sunset tracking
- **Supervisor** - HA Supervisor
- **go2rtc** - WebRTC streaming
- **Backup** - HA Backup
- **Shopping List** - Grocery list
- **Google Translate** - Text-to-speech
- **Met** - Weather forecast (met.no)
- **Radio Browser** - Radio stations
- **Google Cast** - Cast devices (TCL C6K TV)
- **Mobile App** - Alejandro's iPhone, Miriam iPhone
- **ZHA** - Zigbee devices (Sonoff dongle, S60ZBTPF switch)
- **HACS** - Home Assistant Community Store
- **Ring** - Ring integration

## Network Info

- **HA IP**: 192.168.1.100
- **HA VM ID**: 100 (Proxmox)
- **Access**: http://192.168.1.100:8123
- **Proxmox Host**: 192.168.1.134
