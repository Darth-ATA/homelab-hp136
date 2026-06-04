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

## Key Automations

### Gym Water Heater

The `automations.yaml` includes an automation that:
- Triggers when you enter the gym zone (Dreamfit Moratalaz)
- Checks if water heater (termostato) is off
- Sends a notification asking if you want to turn it on
- Waits for response and acts accordingly

### Circadian Lighting - Office Ceiling Fan Light

Automation: `Circadiana: Luz despacho`

Adjusts color temperature and brightness of the FanLamp Pro ceiling fan light throughout the day. Optimized for a west-facing window (268°):

| Time | Color Temp | Brightness | Notes |
|------|-----------|------------|-------|
| 00:00-06:00 | Off | - | No light needed |
| 06:00-08:00 | 2700K (370 mired) | 50% | Sunrise transition |
| 08:00-12:00 | 4500K (222 mired) | 80% | Work mode, cool white |
| 12:00-17:00 | 4000K (250 mired) | 60% | Sun from west compensates |
| 17:00-19:00 | 3000K (333 mired) | 70% | Sunset transition |
| 19:00-21:00 | 2700K (370 mired) | 40% | Warm evening |
| 21:00-23:00 | 2200K (455 mired) | 25% | Night mode |
| 23:00+ | 2000K (500 mired) | 15% | Minimum |

Runs every 15 minutes via `time_pattern` trigger.

### Circadian Fan Speed - Office Ceiling Fan

Automation: `Circadiana: Ventilador despacho`

Adjusts fan speed based on time of day and solar elevation. Since there's no indoor temperature sensor yet, it uses:

- **Time of day** - the west-facing window makes afternoons (12:00-18:00) the hottest period
- **Solar elevation** - when `sun.sun` elevation > 35°, the fan runs faster (75%) vs moderate (50%)

| Time | Fan Speed | Condition |
|------|-----------|-----------|
| 00:00-08:00 | Off | Cool hours |
| 08:00-12:00 | 25% | Light circulation |
| 12:00-18:00 | 50-75% | 75% if sun elevation > 35° |
| 18:00-21:00 | 50% | Moderate |
| 21:00+ | 25% | Night breeze |

**Future upgrade**: Add a temperature sensor (Aqara Zigbee, Shelly, or ESPHome) and switch the fan automation from time+sun logic to direct temperature thresholds.

### Entity IDs

The automations use these entity IDs (verify in HA Developer Tools > States and adjust if needed):

| Entity | ID |
|--------|-----|
| Fan Light | `light.ventilador_de_techo_despacho` |
| Fan | `fan.ventilador_de_techo_despacho` |
| Sun | `sun.sun` (built-in) |

**Note**: ble_adv may expose the fan as `number.<name>_speed` (1-6) instead of a `fan` entity. If so, replace `fan.set_percentage` with `number.set_value` and adjust the range.

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
