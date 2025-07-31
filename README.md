# K3s Raspberry Pi Cluster Setup with Ansible

This repository contains Ansible playbooks to fully automate the setup of a K3s Kubernetes cluster on a group of Raspberry Pi nodes, from OS configuration to application deployment.

## Prerequisites

* **Ansible Controller**: A machine with Ansible installed (e.g., your Mac Mini).
* **Raspberry Pi Nodes**: A set of Raspberry Pis with a fresh install of a compatible OS (e.g., Raspberry Pi OS).
* **SSH Access**: Passwordless SSH access from your Ansible controller to all Raspberry Pi nodes.
* **Required CLI Tools**: `kubectl` and `helm` installed on your Ansible controller.

## Inventory Setup

1.  Open the `hosts` file.
2.  Under the `[the_hive]` group, list the hostnames or IP addresses of your Raspberry Pi nodes. The first node in the list will become the control plane (master).
3.  Update the `ansible_user` variable in `[all:vars]` to match the username on your Raspberry Pi nodes.

---
## Installation and Setup

Run these commands from your Ansible controller to provision the base cluster.

### 1. Initial Node Preparation
Ensures all nodes are up-to-date and have cgroups enabled. These playbooks will reboot the nodes.
```bash
ansible-playbook -i hosts playbooks/initial_update_cluster_playbook.yml
ansible-playbook -i hosts playbooks/enable_cgroups_playbook.yml
```

### 2. Configure Storage

Prepares and mounts a dedicated storage drive on each node using its resilient UUID. This step is required for the application stack.

```bash
ansible-playbook -i hosts playbooks/mount_external_storage_playbook.yml
```

### 3. Install K3s

Installs the k3s server on the first node and joins the rest as workers.

```bash
ansible-playbook -i hosts playbooks/install_k3s_playbook.yml
```

### 4. Fetch kubeconfig for Remote Access

This playbook automatically fetches the cluster configuration file and modifies it for local use.


```bash
ansible-playbook -i hosts playbooks/fetch_kubeconfig_playbook.yml
```

After running, move the generated k3s.yaml file to ~/.kube/config on your local machine. You can now manage the cluster with kubectl.

```bash
mv k3s.yaml ~/.kube/config
kubectl get nodes
```

## Application Stack Deployment

Follow these steps to deploy the full application stack onto your running K3s cluster.

### 1. Prepare Nodes for Longhorn

Installs open-iscsi and other dependencies required by Longhorn.

```bash
ansible-playbook -i hosts playbooks/setup_longhorn_playbook.yml
```

### 2. Create Namespaces and Grafana Secret

Manually create the namespaces for your applications and the secret for the Grafana admin password.

```bash
# Create namespaces
kubectl create namespace monitoring
kubectl create namespace n8n

# Create the Grafana admin secret (replace password)
kubectl create secret generic prometheus-grafana-admin -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='{enter a unique password here}'
```

### 3. Deploy Helm Application Stack

Runs the main playbook to deploy Longhorn, Prefect, Prometheus, and Grafana.

```bash
ansible-playbook -i hosts playbooks/deploy_helm_stack_playbook.yml
```

### 4. Deploy n8n Workflow Automation

Applies the Kubernetes manifests to deploy n8n and its required network service.

```bash
kubectl apply -f non-helm-deployments/n8n.yml
kubectl apply -f non-helm-deployments/n8n-service.yml
```

## Verifying Your Services

Use kubectl port-forward to access the UI for each service. Run each command in a separate terminal.

    Grafana: `kubectl port-forward service/prometheus-grafana 3000:80 -n monitoring` (Access at http://localhost:3000)

    Longhorn: `kubectl port-forward service/longhorn-frontend 8080:80 -n longhorn-system` (Access at http://localhost:8080)

    Prefect: `kubectl port-forward service/prefect-server 4200:4200 -n prefect` (Access at http://localhost:4200)

    n8n: `kubectl port-forward service/n8n-service 5678:5678 -n n8n` (Access at http://localhost:5678)

## Cluster Maintenance and Reset

### Perform a Safe Rolling Upgrade
This playbook safely cordons, drains, updates, and reboots one node at a time.

### Full Cluster Reset (Tear Down)
To completely reset your cluster and remove all applications and data, follow these steps.

```bash
# 1. Uninstall Helm and non-Helm applications
ansible-playbook -i hosts playbooks/uninstall_stack_playbook.yml
kubectl delete -f non-helm-deployments/n8n.yml
kubectl delete -f non-helm-deployments/n8n-service.yml

# 2. Force-delete all persistent data
kubectl delete pvc --all -n monitoring
kubectl delete pvc --all -n prefect
kubectl delete pvc --all -n n8n
kubectl delete pvc --all -n longhorn-system

# 3. (Optional) For a scorched-earth reset, uninstall K3s from all nodes
ansible-playbook -i hosts playbooks/reset_cluster_playbook.yml
```
