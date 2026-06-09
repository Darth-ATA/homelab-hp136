# Homelab Terraform — Useful commands
# Usage: make <target>

.DEFAULT_GOAL := help

SHELL := /bin/bash
PROXMOX_HOST := 192.168.1.134
SSH_KEY := ~/.ssh/homelab_key
LXC_DOCKER := 101
SSH := ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no root@$(PROXMOX_HOST)
PCT_EXEC := $(SSH) "pct exec $(LXC_DOCKER) -- sh -c"

# ── Frigate ────────────────────────────────────────────────────

.PHONY: frigate-info
frigate-info:            ## Show Frigate media disk usage
	$(PCT_EXEC) 'du -sh /root/docker/frigate/media/*/'

.PHONY: frigate-clean
frigate-clean:           ## Delete ALL Frigate videos and snapshots
	$(PCT_EXEC) 'rm -rf /root/docker/frigate/media/clips/* /root/docker/frigate/media/recordings/* /root/docker/frigate/media/exports/*'
	@echo "✓ Frigate media cleaned"

.PHONY: frigate-clean-range
frigate-clean-range:     ## Delete by date range: START=2025-06-01 [END=2025-06-07]
	@test -n "$(START)" || { echo "Usage: make frigate-clean-range START=2025-06-01 [END=2025-06-07]"; exit 1; }
	$(PCT_EXEC) 'UNTIL="$(START)" && [ -n "$(END)" ] && UNTIL="$(END)" && UNTIL_PLUS=$$(date -d "$$UNTIL + 1 day" "+%Y-%m-%d") && echo "→ Deleting Frigate media from $(START) to $$UNTIL..." && find /root/docker/frigate/media/recordings /root/docker/frigate/media/clips -type f -newermt "$(START)" ! -newermt "$$UNTIL_PLUS" -delete 2>/dev/null && find /root/docker/frigate/media/recordings -type d -empty -delete 2>/dev/null && echo "✓ Frigate media from $(START) to $$UNTIL cleaned"'

.PHONY: frigate-restart
frigate-restart:         ## Restart Frigate container
	$(SSH) "pct exec $(LXC_DOCKER) -- docker compose -f /root/docker/frigate/compose.yml restart"

.PHONY: frigate-logs
frigate-logs:            ## Show last 50 Frigate log lines
	$(SSH) "pct exec $(LXC_DOCKER) -- docker logs frigate -n 50"

# ── Terraform ──────────────────────────────────────────────────

.PHONY: plan
plan:                    ## terraform plan
	terraform plan

.PHONY: apply
apply:                   ## terraform apply
	terraform apply

.PHONY: fmt
fmt:                     ## terraform fmt (recursive)
	terraform fmt -recursive

# ── General ────────────────────────────────────────────────────

.PHONY: ssh
ssh:                     ## SSH directly into Proxmox node
	$(SSH)

.PHONY: help
help:                    ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
