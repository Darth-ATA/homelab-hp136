# Samba File Share — shared directory accessible from Mac and PC (LAN + remote via Tailscale)
#
# Provides a single SMB share "shared" backed by the rpool/data/shared ZFS dataset,
# mounted into LXC 101 at /data/shared, exposed by a dperson/samba container.
# Remote access is enabled by configuring LXC 102 (Tailscale) as a subnet router
# for the LAN (10.10.10.0/24).

# Mount point: LXC 101 shared directory bind mount (dedicated ZFS dataset)
resource "null_resource" "docker_shared_mount_point" {
  depends_on = [null_resource.zfs_dataset_shared_create]

  triggers = {
    container_id = 101
    mount_spec   = "/rpool/data/shared,mp=/data/shared"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct set 101 -mp3 /rpool/data/shared,mp=/data/shared'"
  }
}

# Deploy the Samba container on LXC 101 via docker compose.
# The compose file and a generated credential file are written inside LXC 101
# at /root/docker/samba/. The password is generated once and stored in
# .credentials (chmod 600) on the container (never in git).
resource "null_resource" "samba_container_deploy" {
  depends_on = [null_resource.docker_shared_mount_point]

  triggers = {
    container_id = 101
    image        = "dperson/samba:latest"
    share        = "shared"
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 101 -- bash' <<'REMOTE_SCRIPT'
      set -e
      mkdir -p /root/docker/samba
      if [ ! -f /root/docker/samba/.credentials ]; then
        PASS=$(openssl rand -base64 16 | tr -d "/+=" | cut -c1-16)
        printf "user=alejandro\npassword=%s\n" "$PASS" > /root/docker/samba/.credentials
        chmod 600 /root/docker/samba/.credentials
      fi
      . /root/docker/samba/.credentials
      cat > /root/docker/samba/compose.yml <<COMPOSE
services:
  samba:
    image: dperson/samba:latest
    container_name: samba
    restart: unless-stopped
    ports:
      - "139:139"
      - "445:445"
    volumes:
      - /data/shared:/share
    environment:
      - TZ=Europe/Madrid
      - VETO=no
    command: >
      -u "alejandro;$${password}"
      -s "shared;/share;yes;no;no;alejandro;none;alejandro;Shared folder"
COMPOSE
      cd /root/docker/samba && docker compose up -d
REMOTE_SCRIPT
    EOT
  }
}

# Enable Tailscale subnet routing on LXC 102 so the LAN (and the Samba share)
# are reachable from any device on the tailnet.
# NOTE: the advertised route must be approved once in the Tailscale admin console.
resource "null_resource" "tailscale_subnet_router" {
  triggers = {
    container_id = 102
    routes       = "10.10.10.0/24"
  }

  provisioner "local-exec" {
    command = "ssh -i ~/.ssh/homelab_key -o StrictHostKeyChecking=no root@${local.host_ip} 'pct exec 102 -- sh -c \"sysctl -w net.ipv4.ip_forward=1 && echo net.ipv4.ip_forward=1 > /etc/sysctl.d/99-ipforward.conf && tailscale up --advertise-routes=10.10.10.0/24 --accept-routes --accept-dns=false\"'"
  }
}
