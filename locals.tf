# Network addressing — single source of truth for the homelab LAN.
#
# subnet_base ships on the legacy 192.168.1 subnet and flips to "10.10.10"
# at cutover (phase 5 of the subnet-migration change). Every node address and
# firewall destination derives from it, so a renumber is a one-line change
# (fallback subnet: 192.168.77, identical last octets).
locals {
  subnet_base        = "192.168.1" # ships legacy; flip to "10.10.10" at cutover
  legacy_subnet_base = "192.168.1" # documented exception: docker hold address until Apply C
  new_subnet_base    = "10.10.10"  # staging target: eth1 (docker) + host dual-stack before the flip

  lan_cidr    = "${local.subnet_base}.0/24"
  lan_gateway = "${local.subnet_base}.1"
  lan_dns     = "${local.subnet_base}.2"

  # Last octets per node (see NETWORK.md allocation table).
  node_ips = {
    adguard     = 2
    ha          = 100
    tailscale   = 102
    docker      = 142
    vaultwarden = 144
    jellyfin    = 145
    host        = 134
  }

  host_ip = "${local.subnet_base}.${local.node_ips.host}"
}
