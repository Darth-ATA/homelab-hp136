# Bluetooth Ceiling Fan Setup (Despacho)

**Fan:** FanLamp Pro (BLE Advertising) via AliExpress
**App:** FanLamp Pro
**HA Integration:** `ha-ble-adv` by NicoIIT
**Device:** Realtek Bluetooth Radio (0bda:c821, RTL8821C) built-in on N100

## Overview

The N100's built-in Bluetooth cannot be shared between the Proxmox host and a VM. The device must be detached from the host kernel (`btusb`) and passed through to the Home Assistant VM via USB passthrough.

## Step-by-Step

### 1. Blacklist btusb on Proxmox Host

```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134

# Create blacklist config
echo 'blacklist btusb' > /etc/modprobe.d/blacklist-btusb.conf

# Rebuild initramfs (required on Debian-based Proxmox)
update-initramfs -u -k all

# Reboot to apply
reboot
```

After reboot, verify btusb is no longer loaded:

```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "lsmod | grep btusb"
# Should return nothing (btusb not loaded)
```

### 2. Apply Terraform BT Passthrough

The Terraform config (`home_vm.tf`) handles this:
- Declares `usb { host = "0bda:c821" }` in the VM resource
- Uses `ignore_changes = [usb]` because the API token cannot pass USB devices
- A `null_resource` with `local-exec` via SSH runs `qm set` to attach the device

```bash
cd /Users/alejandrotorresaguilera/homelab-terraform
terraform apply -target=null_resource.bluetooth_usb_passthrough
```

Verify the device is attached to the VM:

```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "qm config 100 | grep usb"
# Expected: usb1: host=0bda:c821
```

### 3. Verify Bluetooth in Home Assistant

Access the HA VM terminal:

```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "qm terminal 100"
# Login to HAOS CLI
```

Or via SSH add-on in HA. Check Bluetooth is visible:

```bash
lsusb
# Should show: Realtek Bluetooth Radio on Bus 009 Device 003

# Check BT adapter
hciconfig -a
# Should show hci0 with BD Address
```

### 4. Install ha-ble-adv via HACS

1. Go to **Settings → Devices & Services → HACS → Integrations**
2. Click the **three dots (⋮) → Custom repositories**
3. Add: `https://github.com/NicoIIT/ha-ble-adv` (category: Integration)
4. Click **Install** on the `ha-ble-adv` card
5. Restart Home Assistant when prompted

### 5. Configure via Duplicate Config Method

1. In the FanLamp Pro app on your phone, **pair the fan** if not already paired
2. In Home Assistant, go to **Settings → Devices & Services → Add Integration**
3. Search for **ble_adv** and select it
4. Follow the Duplicate Config flow:
   - Press the **Pair** button in the FanLamp Pro app while HA is listening
   - ble_adv will discover the fan
5. Configure the device:

| Setting | Value |
|---------|-------|
| Device | FanLamp Pro |
| Codec | `fanlamp_pro_v3` |
| Fan type | 6-speed |
| Presets | breeze, sleep |
| Light type | CWW (2000K-6535K) |
| BT adapter | hci`/MAC` (use the MAC shown from `hciconfig`) |
| Area | Despacho |

### 6. Final Verification

- The fan should appear as a device in HA
- Test: turn on/off fan, change speed, toggle light, adjust brightness/color temp
- Test presets: breeze mode, sleep mode
- If the fan disconnects, the HA VM may need a reboot to re-initialize the BT adapter

## Troubleshooting

### btusb still loaded after blacklist

```bash
ssh -i ~/.ssh/homelab_key root@192.168.1.134
lsmod | grep btusb
# If still loaded, check initramfs was rebuilt
ls -la /etc/modprobe.d/blacklist-btusb.conf
update-initramfs -u -k all
```

### USB device not visible in HA

```bash
# Check qemu config
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "qm config 100 | grep usb"

# Rerun terraform if missing
terraform apply -target=null_resource.bluetooth_usb_passthrough

# Restart the VM from Proxmox UI or CLI
ssh -i ~/.ssh/homelab_key root@192.168.1.134 "qm reboot 100"
```

### ble_adv not discovering fan

1. Verify BT adapter is working inside HA (`hciconfig -a`)
2. Re-run Duplicate Config: press the Pair button in the FanLamp Pro app
3. Make sure the fan is powered on and in pairing range

## Files

| File | Purpose |
|------|---------|
| `home_vm.tf` | Terraform USB passthrough + null_resource |
| `CLAUDE.md` | AI agent context (summary) |
| `docs/bluetooth-ceiling-fan-setup.md` | This file — full setup guide |
