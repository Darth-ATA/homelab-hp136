# Spec: ha-air-quality-47 — Air Quality Notifications

## Requirements

### REQ-001: Bad air quality detection
- **ID**: REQ-001
- **Description**: When CO₂ level exceeds 1000 ppm and air quality state is `normal`, notify user(s) to open windows
- **Trigger**: `sensor.meter_pro_co2_9540_dioxido_de_carbono` numeric_state above 1000
- **Debounce**: 5 minutes above threshold before firing
- **State machine**: `input_select.air_quality_state` transitions from `normal` → `bad`

### REQ-002: Air quality recovery notification
- **ID**: REQ-002
- **Description**: When CO₂ level drops below 800 ppm and air quality state is `bad`, notify user(s) that air quality has recovered
- **Trigger**: `sensor.meter_pro_co2_9540_dioxido_de_carbono` numeric_state below 800
- **Debounce**: 5 minutes below threshold before firing
- **State machine**: `input_select.air_quality_state` transitions from `bad` → `normal`

### REQ-003: No notification spam
- **ID**: REQ-003
- **Description**: Notifications only fire on state transitions. Same notification is NOT repeated while state stays the same, regardless of sensor fluctuations
- **Implementation**: State machine in `input_select.air_quality_state` with states: `normal`, `bad`

### REQ-004: Notify both phones
- **ID**: REQ-004
- **Description**: Both Alejandro and Miriam receive notifications
- **Channels**:
  - `notify.mobile_app_alejandros_iphone`
  - `notify.mobile_app_miriam_iphone`
- **Note**: Use `notify.send_message` service with both as targets, same pattern as existing ventilation notifications (automation id: 1768000000001, lines 570-598 of automations.yaml)

### REQ-005: Notification content
- **ID**: REQ-005
- **Description**: Both messages in español ibérico (no voseo)
- **Bad air notification**: Notify to open windows (title about air quality, message asking to ventilate)
- **Recovery notification**: Notify that air is good again and can close windows

### REQ-006: Sensor unavailability handling
- **ID**: REQ-006
- **Description**: If sensor state is `unavailable`, `unknown`, or `none`, the automation should not fire any notification
- **Pattern**: Same as existing ventilation automation (line 137 of automations.yaml checks for unavailable/unknown/none)

## State Machine

### input_select.air_quality_state

Options:
- `normal` (initial) — CO₂ < 800 ppm, air quality is good
- `bad` — CO₂ > 1000 ppm, air quality is poor, ventilation recommended

Transitions:
- `normal` → `bad`: Trigger when CO₂ > 1000 ppm for 5 min → notify "open windows"
- `bad` → `normal`: Trigger when CO₂ < 800 ppm for 5 min → notify "air quality recovered"

## Acceptance Criteria

### Scenario 1: Bad air quality
1. Given the study CO₂ sensor reads 1200 ppm for 5 minutes
2. When the automation evaluates
3. Then `input_select.air_quality_state` changes to `bad`
4. And both phones receive a notification to open windows
5. And no further notification is sent while state remains `bad`

### Scenario 2: Air quality recovery
1. Given `input_select.air_quality_state` is `bad`
2. And the CO₂ sensor drops to 700 ppm for 5 minutes
3. When the automation evaluates
4. Then `input_select.air_quality_state` changes to `normal`
5. And both phones receive a notification that air quality recovered

### Scenario 3: No spam on sensor fluctuation
1. Given CO₂ fluctuates between 900-1100 ppm without sustaining 5 min above 1000 ppm
2. Then no state transition occurs
3. And no notification is sent

### Scenario 4: Sensor unavailable
1. Given the CO₂ sensor reports `unavailable`
2. Then no notification is fired
3. And the state machine retains its last known state

## Dependencies
- Existing Switchbot Meter Pro CO2 9540 sensor reporting CO₂ data to HA
- `notify.send_message` service available
- No additional integrations required

## Out of Scope
- No dashboard or Lovelace UI changes
- No fan/window automation changes
- No integration with existing ventilation state machine
- No auto-open/close windows (manual only)
- No other rooms or additional sensors
