# K3s Raspberry Pi cluster

These Ansible playbooks prepare Raspberry Pi nodes, install a single-server K3s cluster, and deploy Prefect, Prometheus, Grafana, n8n, and Pi-hole. The first host in `hosts` is the K3s server; the rest are agents. Run commands from the repository root on the Ansible controller.

## Prerequisites

- Raspberry Pi OS or another Debian-based OS on the nodes, with passwordless SSH and sudo access. Use 64-bit OS images for the application images.
- Ansible with the `community.general`, `ansible.posix`, and `kubernetes.core` collections. The Python interpreter running Ansible needs the `kubernetes` package. The controller also needs Helm 3.12+ and `kubectl`.
- Edit `hosts` for your node names, addresses, and SSH user. Give every Pi a reserved address and set `ansible_host=<address>` for each entry, so future Ansible runs do not depend on Pi-hole DNS.
- Edit `playbooks/storage_vars.yml` for the actual storage drives on **every** node. The defaults assume the 512 GB drive is `/dev/sda` and the 128 GB drive is `/dev/sdb`. The mount playbook partitions and formats every listed device; its capacity checks reject swapped drives. Back up any existing data and verify device names and sizes on every node before running it. K3s stores local volumes under `local_storage_path` on the first listed drive; changing either storage path after installation requires a data migration.
- Reserve the first K3s node's LAN IPv4 address in your router and put it in `playbooks/network_vars.yml` as `lan_ip`. The default local domain is `hive.home`. Keep your router's current DNS setting until Pi-hole has been deployed and tested.

### Using the 128 GB and 512 GB USB drives

Keep application PVCs on the 512 GB drive. K3s `local-path` places each PVC on one node, so these drives do not form a shared pool or provide failover. K3s data (including container images and the server database on the first node) uses the 128 GB drive; the OS, some kubelet files, and system logs remain on the SD card. Do not configure both drives as interchangeable `local-path` directories: the provisioner does not balance by free capacity or enforce PVC size limits.

The OS is on a separate 256 GB SD card. Run `lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS` on **each** Pi and identify both USB drives. The mount task refuses a device that contains `/` or a boot mount.

The checked-in layout uses the 512 GB drive first for PVCs and the 128 GB drive for K3s runtime. It is correct **only if** `lsblk` confirms `/dev/sda` is the 512 GB drive and `/dev/sdb` is the 128 GB drive on every Pi:

```yaml
disks_to_mount:
  - { device: /dev/sda, partition: /dev/sda1, path: /mnt/k3s-storage, expected_size_gb: 512 }
  - { device: /dev/sdb, partition: /dev/sdb1, path: /mnt/k3s-system, expected_size_gb: 128 }
local_storage_path: /mnt/k3s-storage/pvc
k3s_data_dir: /mnt/k3s-system/k3s
k3s_data_mount: /mnt/k3s-system
```

`expected_size_gb` makes the mount playbook reject a drive with the wrong capacity before partitioning. The shared `storage_vars.yml` currently assumes the same device names on every Pi; if enumeration differs, use stable device paths and adjust the configuration before running it. Choose the layout before the first K3s install, since moving an existing data directory or PVCs needs a migration. After installation, check `df -h /mnt/k3s-storage /mnt/k3s-system`. Keep free space on both drives and send backups to storage outside the cluster.

## Install the cluster

```bash
ansible-playbook -i hosts playbooks/initial_update_cluster_playbook.yml
ansible-playbook -i hosts playbooks/enable_cgroups_playbook.yml
ansible-playbook -i hosts playbooks/mount_external_storage_playbook.yml
ansible-playbook -i hosts playbooks/install_k3s_playbook.yml
ansible-playbook -i hosts playbooks/fetch_kubeconfig_playbook.yml
```

The fetched `k3s.yaml` contains cluster administrator credentials and is ignored by Git. Point `kubectl`, Helm, and the local Ansible Kubernetes modules at it:

```bash
export KUBECONFIG="$PWD/k3s.yaml"
kubectl get nodes
```

Wait until all nodes report `Ready`, then create the application secrets before deploying the stack. Use at least 16 URL-safe characters (letters, digits, `.`, `_`, `~`, `-`) for a new Prefect password because the chart builds a database URL from it. Keep the Prefect password and n8n encryption key unchanged on future upgrades. Set `LAN_DOMAIN` below to the same domain as `lan_domain` in `playbooks/network_vars.yml`.

```bash
LAN_DOMAIN=hive.home
printf 'Prefect database password: '
read -r -s PREFECT_POSTGRES_PASSWORD
printf '\n'
export PREFECT_POSTGRES_PASSWORD
printf 'Grafana admin password: '
read -r -s GRAFANA_PASSWORD
printf '\n'
printf 'Pi-hole admin password: '
read -r -s PIHOLE_PASSWORD
printf '\n'
printf 'LAN dashboard password: '
read -r -s LAN_DASHBOARD_PASSWORD
printf '\n'
for ns in monitoring n8n pihole prefect; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl create secret generic prometheus-grafana-admin -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_PASSWORD"
kubectl create secret generic n8n-secrets -n n8n \
  --from-literal=N8N_ENCRYPTION_KEY="$(openssl rand -hex 32)" \
  --from-literal=N8N_HOST="n8n.$LAN_DOMAIN" \
  --from-literal=N8N_PORT=5678 \
  --from-literal=N8N_PROTOCOL=http
kubectl create secret generic pihole-admin -n pihole \
  --from-literal=password="$PIHOLE_PASSWORD"
LAN_AUTH_LINE="admin:$(printf '%s' "$LAN_DASHBOARD_PASSWORD" | openssl passwd -apr1 -stdin)"
for ns in prefect monitoring; do
  kubectl create secret generic lan-basic-auth -n "$ns" \
    --from-literal=auth="$LAN_AUTH_LINE"
done
unset GRAFANA_PASSWORD PIHOLE_PASSWORD LAN_DASHBOARD_PASSWORD LAN_AUTH_LINE
ansible-playbook -i hosts playbooks/deploy_helm_stack_playbook.yml
```

If a secret already exists, keep or update it rather than recreating it. The stack playbook checks all required secrets and never replaces them. It installs the official n8n Helm chart at version 1.14.0 as a single instance with SQLite on a K3s `local-path` volume. Pi-hole uses the official `pihole/pihole:2026.10.0` image, stores its data on `local-path`, and publishes DNS on TCP and UDP port 53 through K3s ServiceLB. K3s's bundled Traefik routes the web UIs by hostname on port 443. The Prefect worker creates its named Kubernetes work pool on first start. Prefect's chart handles database migrations. K3s will refuse to start on a node if its configured storage mount is missing.

Check the deployed resources:

```bash
kubectl get pods,pvc -n prefect
kubectl get pods,pvc -n monitoring
kubectl get pods,pvc -n n8n
kubectl get pods,pvc,svc -n pihole
kubectl get storageclass local-path
kubectl get ingress -A
```

Before changing your router's DHCP DNS setting, verify that the Pi-hole service includes the first node's IP and answers a local name (replace the example IP):

```bash
kubectl get service pihole-dns -n pihole
nslookup n8n.hive.home 192.168.1.10
```

Then set the router's LAN DHCP DNS server to the reserved `lan_ip` and renew clients' DHCP leases. If the router also advertises IPv6 DNS, update that setting so clients do not bypass Pi-hole. Keep Pi-hole's DHCP server disabled; your router continues to provide DHCP. Every device that receives Pi-hole as DNS can use these URLs without port-forwarding:

| Service | LAN URL |
| --- | --- |
| n8n | `https://n8n.hive.home/` |
| Prefect | `https://prefect.hive.home/` |
| Grafana | `https://grafana.hive.home/` |
| Prometheus | `https://prometheus.hive.home/` |
| Pi-hole | `https://pihole.hive.home/admin/` |

Replace `hive.home` if you changed `lan_domain`. The first installation uses Traefik's generated certificate, so browsers will warn that HTTPS is untrusted until you configure a trusted LAN certificate. Prefect and Prometheus also require the `admin` / LAN dashboard password above. Pi-hole uses its own password; Grafana and n8n use their own logins. These names resolve only on your LAN, so external services cannot call n8n webhooks without a separate public ingress. Because Pi-hole is in this single-server cluster, cluster downtime also interrupts LAN DNS; restore the router's previous DNS setting if you need name resolution during an outage.

## Backups

K3s `local-path` volumes stay on one Pi. A pod can restart, but it cannot move its data to another node if that Pi or its drive fails. PVC size requests are not disk quotas, so watch free space on each storage drive with `df -h /mnt/k3s-storage`. Before depending on these apps, arrange regular off-cluster backups. The included backup playbook pauses the entire cluster, archives every node's local volumes plus the K3s server datastore and token, copies the archives to the Ansible controller, and attempts to restart K3s even if a backup step fails. Run it during a maintenance window: Pi-hole DNS and the web apps are unavailable while it runs. The destination and each Pi's storage drive need enough temporary free space for an archive; keep the final copies on a separate disk or backup system.

```bash
mkdir -p "$HOME/Backups/the_hive"
export HIVE_BACKUP_DIR="$HOME/Backups/the_hive"
ansible-playbook -i hosts playbooks/backup_cluster_playbook.yml
```

Run this at least weekly and before upgrades or removal; schedule it on the controller only if the planned outage is acceptable. A successful run creates a timestamped directory with a `COMPLETE` file, one `*-volumes.tar.gz` per Pi, `k3s-server.tar.gz`, and copies of the inventory and storage settings. Treat those archives as secrets: they contain application data, credentials, and the K3s server token. Periodically test extraction and a restore on spare hardware. For a full cluster restore, put each node's local volume files back at the same `local_storage_path` before starting K3s, restore the server database and token to the configured `k3s_data_dir` from the server archive, and keep the original node names. Restoring individual apps requires their original PVC metadata and node placement; a fresh deployment alone will not reconnect the old local volume directories. See the [K3s SQLite restore instructions](https://docs.k3s.io/datastore/backup-restore).

## Maintenance and removal

`playbooks/rolling_cluster_upgrade.yml` drains, updates, and reboots one node at a time, with the server last. It verifies the storage mounts after each reboot, uncordons the recovered node so its local PVC pods can restart, then waits for all Deployments and StatefulSets to finish rolling out before continuing. A failed drain uncordons the node and stops; a failure after package updates leaves the node cordoned for inspection. This upgrades OS packages, not the pinned K3s binary. Run it only with a healthy cluster, a working controller kubeconfig, and a recent off-cluster backup:

```bash
ansible-playbook -i hosts playbooks/rolling_cluster_upgrade.yml
```

The swap playbook is optional and is not part of the standard K3s install. Kubernetes swap behavior depends on kubelet configuration, and swap on a Pi's SD card can cause severe I/O pressure. Review the node's K3s and kubelet settings before running `playbooks/create_swap_playbook.yml`.

To remove the application stack, run:

```bash
ansible-playbook -i hosts playbooks/uninstall_stack_playbook.yml
```

This removes application namespaces, including Pi-hole and their persistent volume claims. K3s `local-path` then deletes the associated local data. Take and verify a backup first. Restore the router's previous DNS setting before removing Pi-hole. After the stack has been removed, optionally uninstall K3s from all nodes:

```bash
ansible-playbook -i hosts playbooks/reset_cluster_playbook.yml
```

The K3s uninstall scripts remove cluster state from the nodes. Back up any data you need before either removal step.
