# Recovering the Proxmox homelab

## Before restoring

1. Contact the repository owner. Record the affected VMID, symptoms and last known good backup time. For a full disk or a `lock: mounted` error, check active PVE tasks and [known issues](docs/troubleshooting.md) first. Do not unlock a guest during an active backup or restore.
2. On the node, list completed archives with `pvesm list local --content backup --vmid <id>` and check the corresponding **Tasks** log for a successful vzdump. Pick **one exact archive**, not a wildcard. Prefer the most recent known-good copy from before the incident.
3. `local` (`/var/lib/vz/dump`) stores archives; `local-zfs` stores guest disks. Local backups do **not** protect against loss of the host pool. After disk loss, first recover an independent copy. Terraform can recreate configuration, not lost guest data.
4. Check `pvesm status` for restore capacity. Use an **unused VMID** for a rehearsal or side-by-side restore. Leave the restored guest stopped until its networking, devices and bind mounts are isolated: duplicate IPs, shared writable datasets and real Home Assistant automations are unsafe in a test restore.

## Restore a VM (Home Assistant, VM 100)

On the node, substitute the absolute archive path and unused numeric ID:

```bash
qmrestore <archive.vma.zst> <unused-vmid> --storage local-zfs
qm config <unused-vmid>
```

Verify boot disk, NIC and Zigbee/Bluetooth passthrough against `home_vm.tf`. For a test, disconnect the virtual NIC and detach physical devices before boot. Check the console and HA startup. For production cutover, stop the old guest before attaching its devices or bringing the restored instance onto the LAN. Verify HA integrations, networking and a recent configuration change.

## Restore or recreate a container (CT 101–105)

```bash
pct restore <unused-vmid> <archive.tar.zst> --storage local-zfs
pct config <unused-vmid>
```

Compare the network, device permissions and `mpN` entries to the guest's Terraform configuration. **Bind-mounted data is not in the container archive.** For CT 101, verify the media, torrents, Soulseek and shared datasets on the host before reconnecting the production mounts. For CT 105 check the media mount and iGPU. Do not point a test guest at writable production paths.

Start the isolated guest and check its console and service status. At cutover, verify the affected workload (e.g. DNS queries for AdGuard, the Arcane-managed projects for Docker, playback for Jellyfin). Keep the old instance/archive until verification succeeds. Returning to a production VMID is a separate owner-controlled downtime operation; never force an in-place restore as a test.

If no usable container archive exists, the owner can provision a **blank** Terraform-managed container from its declared template, then restore application data separately. Review the plan for the intended VMID only; stop on unexpected replacements. Do not recreate a stateful guest just to resolve Terraform drift.

## Rebuilding the node

1. Recover storage and independently saved archives before provisioning guests. Re-establish the node name, storage IDs, network and physical passthrough prerequisites.
2. Restore data-bearing guests first. In particular restore the Docker guest and its Garage state service before expecting to use the remote Terraform backend. Verify the state is available; do not initialize an empty replacement state over it.
3. Reconcile the restored guest IDs with existing Terraform state and review a plan before applying configuration. A `null_resource` recorded in surviving state does not automatically rerun on a rebuilt host: verify deployed scripts, cron entries and APT policy against the [maintenance schedule](README.md#maintenance), then explicitly redeploy missing host configuration. Verify the manually managed CT 101 backup job in PVE as well.
4. Verify guest services and the next successful backup for each guest. Run an isolated restore drill monthly, using the steps above. A passing health check is not proof that a backup can be restored.
