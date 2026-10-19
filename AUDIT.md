# Setup playbook audit — 2026-10-19

This repository contains Ansible playbooks, not Jupyter notebooks. The audit covered every playbook in `playbooks/`, the included disk task, inventory, n8n deployment, helper script, and README. It checked the intended installation and removal order, rerun behavior, current upstream configuration keys, credentials, and local syntax. No install, backup, upgrade, or uninstall was run against the cluster.

| Area | Finding and correction |
| --- | --- |
| Node updates | Apt's lock timeout replaces an unbounded shell wait; nodes reboot only when packages change. |
| Cgroups | The original playbook removed and readded both kernel arguments on every run, forcing every node to reboot. It now supports both Raspberry Pi boot paths, removes duplicates once, and reboots only when the command line changes. |
| Storage | The mount task used the nonexistent `ansible.builtin.mount` module. It now uses `ansible.posix.mount`, rejects devices carrying the OS root or boot mount, and checks expected drive capacity. The configured layout assumes a separate 256 GB OS SD card, a 512 GB USB drive at `/dev/sda` for `local-path` PVCs, and a 128 GB USB drive at `/dev/sdb` for K3s runtime data. Verify those paths on every node before use because partitioning and formatting can destroy data. K3s services require both mounts, so a missing drive does not silently redirect volumes or runtime data to the OS card. |
| K3s | The join token was written to a shared controller `/tmp` path. It is now read into Ansible memory with output hidden, and installer pipelines fail if the download fails. Existing `creates` guards prevent a rerun from upgrading K3s. |
| Kubeconfig | Fetching produces an administrator kubeconfig in the repo root. It is now ignored by Git; the README sets `KUBECONFIG` for controller commands. |
| Longhorn removal | Longhorn and its extra node dependencies were removed from the fresh-install path. All application PVCs now request K3s `local-path` storage. Each volume is bound to one node and does not fail over if that node or drive fails. Local-path PVC size requests are not enforced as disk quotas. |
| Prefect | PostgreSQL persistence was under the wrong key. It now uses `postgresql.primary.persistence` and a persistent password supplied at runtime. The old one-time migration receipt and manual work-pool creation could skip needed work after chart upgrades; current Prefect charts handle migrations and worker pool creation. |
| Monitoring | The stack previously overwrote the manually created Grafana admin secret with a fixed password. It now checks for the expected secret and leaves its credentials intact. |
| n8n | Replaced the raw manifest and mutable `latest` image with n8n's official OCI Helm chart pinned to 1.14.0. It runs standalone with SQLite on a local PVC, uses the operator's persistent encryption key, and recreates the pod during upgrades to avoid attaching the volume twice. Its editor and webhook URLs now use the LAN ingress hostname. |
| Pi-hole and LAN access | The stack now deploys Pi-hole's official pinned container with a local PVC, publishes DNS through K3s ServiceLB, and creates local DNS records and Traefik HTTPS ingresses for the five web interfaces. Prefect's browser API URL points at its ingress. Prefect and Prometheus ingresses have basic authentication. The first node's reserved LAN address is required in `playbooks/network_vars.yml`; browsers initially see Traefik's generated certificate. |
| Backup | A maintenance-window playbook now stops K3s and pod containers using the configured K3s data directory, copies all local PVC files plus the K3s server database and token to an off-cluster directory on the controller, and attempts to restart K3s in an `always` block. Backups contain credentials and require protected storage. Scheduling and restore testing remain operator tasks. |
| Removal | The uninstall playbook removes application Helm releases and namespaces. Deleting their local PVCs also deletes the associated data; take and verify a backup before teardown. |
| Cluster reset | Missing uninstall scripts are skipped; a real uninstall error now stops the playbook. The K3s uninstall scripts receive the custom data directory so they remove the correct runtime files. |
| Rolling upgrades | Drain respects Kubernetes eviction policy and waits for deletion. Workers are upgraded before the single server. A failed drain uncordons the node; after reboot, configured mounts and node readiness are checked, then the node is uncordoned before waiting for every Deployment and StatefulSet to recover. This ordering is required for node-bound `local-path` PVCs. |
| Swap | The optional playbook now activates `/swapfile` only when inactive and enforces its file permissions on reruns. The README no longer places it in the standard install sequence. |
| README | Removed the nonexistent swap filename, duplicate n8n deployment, and malformed cleanup shell commands. It now documents prerequisites, secrets, verification, and the destructive steps. |

## Remaining checks before deployment

1. Verify the actual node names, 64-bit OS architecture, 128/512 GB USB drive names on each node, and first node's reserved LAN IPv4 address before installing the fresh cluster. Set that address in `playbooks/network_vars.yml`. The saved `longhorn-ns.json` and `monitoring-ns.json` snapshots describe a previous cluster and do not apply to the newly imaged nodes.
2. Check the versions of the Prefect and Prometheus charts against the new cluster before deployment or upgrade. Those chart versions remain unpinned, so reruns can introduce upstream changes. The n8n chart is pinned to 1.14.0 and requires Kubernetes 1.25+.
3. Keep the Prefect database password and n8n encryption key used on the initial installation for every upgrade. Changing either without a data migration breaks access to existing data.
4. Test the full install, backup, restore, and teardown on a disposable cluster with the same architecture and disk layout. Confirm `local-path` PVCs land on the mounted drive, the Pi-hole LoadBalancer has the first node's IP, DNS answers local records on TCP and UDP port 53, and the HTTPS ingresses route correctly. Local syntax checks cannot prove chart rendering or application readiness against this cluster.

## Verification performed

- `ansible-playbook --syntax-check` passed for all current playbooks.
- `git diff --check` passed.
- A local Ansible assertion verified that the LAN ingress annotations render as a map and Pi-hole's resolver list renders as a list.
- The n8n values were checked against the upstream 1.14.0 chart. The sandbox cannot resolve `ghcr.io`, so an OCI chart render was not available locally.
- No live cluster mutations were performed.

## Upstream references

- [K3s Raspberry Pi requirements](https://docs.k3s.io/installation/requirements)
- [K3s local storage](https://docs.k3s.io/add-ons/storage)
- [K3s server and agent data directories](https://docs.k3s.io/cli/server)
- [K3s install, killall, and uninstall scripts](https://github.com/k3s-io/k3s/blob/main/install.sh)
- [Local Path Provisioner limitations](https://github.com/rancher/local-path-provisioner)
- [Kubernetes node drain](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
- [K3s SQLite backup and restore](https://docs.k3s.io/datastore/backup-restore)
- [K3s pod shutdown behavior](https://docs.k3s.io/upgrades/killall)
- [Prefect server chart values](https://github.com/PrefectHQ/prefect-helm/blob/main/charts/prefect-server/values.yaml)
- [Prefect worker chart guidance](https://github.com/PrefectHQ/prefect-helm/blob/main/charts/prefect-worker/README.md)
- [Official n8n Helm chart 1.14.0](https://github.com/n8n-io/n8n-hosting/tree/v1.14.0/charts/n8n)
- [Pi-hole Docker configuration](https://docs.pi-hole.net/docker/configuration/)
- [Pi-hole Docker release 2026.10.0](https://github.com/pi-hole/docker-pi-hole/releases/tag/2026.10.0)
- [K3s ServiceLB and Traefik](https://docs.k3s.io/networking/networking-services)
- [ICANN's discussion of .home name collisions](https://www.icann.org/en/board-activities-and-meetings/materials/preliminary-report-regular-meeting-of-the-icann-board-02-11-2017-en)
- [Kubernetes swap behavior](https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/)
