# Storage Configuration for Proxmox
# References:
# - Dir-type storage (local): Supports backup, iso, snippets, vztmpl
# - ZFS pool storage (local-zfs): Supports images, rootdir (NOT backup)

# Local directory storage (supports backup content type)
# NOTE: The bpg/proxmox provider has a known bug with the `nodes` attribute for directory storage
# To import existing local storage into Terraform state:
# terraform import proxmox_storage_directory.local local
# Uncomment only if the provider bug with `nodes` attribute is resolved
# resource "proxmox_storage_directory" "local" {
#   id       = "local"
#   nodes    = [var.proxmox_node_name]
#   path     = "/var/lib/vz"
#   content  = ["backup", "iso", "snippets", "vztmpl"]
#   shared   = true

#   lifecycle {
#     prevent_destroy = true
#   }
# }

# ZFS zpool storage (managed by Terraform to prevent accidental deletion)
# Supports images and rootdir content types (NO backup - ZFS does not support backup content type)
# prevent_destroy lifecycle rule ensures Terraform will never delete this storage from Proxmox
resource "proxmox_storage_zfspool" "local_zfs" {
  id       = "local-zfs"
  nodes    = [var.proxmox_node_name]
  content  = ["images", "rootdir"]
  zfs_pool = "rpool/data"

  lifecycle {
    prevent_destroy = true
  }
}
