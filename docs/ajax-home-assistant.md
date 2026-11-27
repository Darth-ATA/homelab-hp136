# Ajax alarm in Home Assistant — owner setup

**Status (#72):** Aegis is the recommended approach, not a verified installation. The hub model, firmware and entities have not been confirmed. Do not use the HA panel as the sole means of controlling the alarm.

## Why Aegis?

[Aegis for Ajax](https://github.com/bvis/aegis-hass) supports both panel control and device updates through the Ajax cloud. The [native SIA integration](https://www.home-assistant.io/integrations/sia/) is an alternative for receiving events, but cannot arm or disarm the panel. [ajax-security-hass](https://github.com/foXaCe/ajax-security-hass) would require enterprise API access or a proxy. Use Aegis only if the owner accepts a third-party component handling an Ajax login in HA.

## Install and pair (owner, in the UI)

1. In the Ajax app, select the space, then **Devices → hub**. Note the exact model and firmware (OS Malevich version). Compare the hardware, HA version and account requirements with the Aegis release documentation before installing. Stop if compatibility is unclear. Keep hub identifiers and account details private.
2. Take a private HA backup. In HACS, open **Custom repositories**, add `https://github.com/bvis/aegis-hass` with type **Integration**, then find **Aegis for Ajax** and download a compatible release. Restart Home Assistant Core; reloading YAML is not sufficient to load a new custom integration.
3. Go to **Settings → Devices & services → Add integration → Aegis for Ajax**. Sign in through the integration flow using an Ajax account authorized for the intended hub and arm/disarm operations. Complete any authentication prompts locally. This creates a runtime config entry, not a Terraform resource or YAML declaration. Never copy credentials, config entries, logs or backup files into Git or the issue.

## Acceptance checks

- Open the Aegis integration entry. Confirm the expected hub and devices are present. In **Developer Tools → States**, identify the actual `alarm_control_panel` entity and a contact sensor from this entry. Compare the panel state and available sensor readings (e.g. battery) with the Ajax app. Do not assume entity IDs from device names.
- With the system disarmed, use a contact that is safe to open and not configured for 24-hour alarming. Open and close it once. Watch for both corresponding transitions in HA without reloading; check the sensor history or Activity timestamps. If no transitions appear, leave real-time detection unverified.
- Arrange a safe test window with occupants and the monitoring provider if applicable. Have the Ajax app or keypad ready. With zones clear, arm from the **HA panel controls**, allow for exit delay, and confirm the final armed state independently in Ajax. Disarm from HA and confirm there too. Restore the original mode and end any monitoring test window. If HA control fails, use the official controls. Do not test panic or trigger dispatch.
- Only after these checks should a Frigate automation be bound to the observed entities. No automation is installed by this procedure; there is no trace to inspect yet.

If abandoning the integration, confirm the alarm mode in the Ajax app, remove the Aegis entry from **Devices & services**, then remove the download in HACS and restart HA. Confirm the official controls still work.
