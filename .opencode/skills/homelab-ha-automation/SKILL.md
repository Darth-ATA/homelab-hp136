---
name: homelab-ha-automation
description: "Trigger: changes to ha-config/ (automations.yaml, scripts.yaml, configuration.yaml) or any Home Assistant automation. Requires validation in the real homelab before considering the change done."
license: MIT
metadata:
  author: gentleman-programming
  version: "1.0"
---

## Activation Contract

Use this skill when the work touches files under `ha-config/` or any Home Assistant automation of the homelab.

## Hard Rules

- Never assume a Home Assistant automation change works just because the YAML is valid.
- After editing `ha-config/automations.yaml` (or `scripts.yaml` / `configuration.yaml`), execute:
  1. Local YAML syntax validation.
  2. Deploy to the homelab with `./scripts/deploy-ha-config.sh`.
  3. Review Home Assistant logs (`ha core logs`) to confirm there are no automation errors or related tracebacks.
  4. If the change affects a concrete scenario (e.g. washing machine cheap-hour), verify the state of the involved entities in HA Developer Tools or reproduce the trigger if it's safe to do so.
- If you don't have access to the homelab, stop and ask the user before continuing.

## Decision Gates

| Situation | Action |
| --- | --- |
| `ha-config/automations.yaml` is edited | Deploy and review logs before closing the task |
| YAML has a syntax error | Fix locally before deploying |
| No access to the homelab | Stop and ask the user |
| There are errors in HA logs | Do not consider the task done; fix and re-deploy |

## Execution Steps

1. Identify which `ha-config/` files will be touched.
2. Validate YAML locally (`python3 -c "import yaml; yaml.safe_load(open(...))"`).
3. Run `./scripts/deploy-ha-config.sh <file>` with the modified file(s).
4. Review HA logs: `ha core logs | grep -i <automation alias or id>`.
5. Report to the user which files were deployed, whether HA Core restarted without errors, and what was observed in the logs.

## Output Contract

- Indicate which files were deployed.
- Indicate whether HA Core restarted without errors.
- Indicate what was observed in the logs (errors or clean).
