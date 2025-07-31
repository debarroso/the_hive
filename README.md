# K3s Raspberry Pi Cluster Setup with Ansible

This repository contains Ansible playbooks to fully automate the setup of a K3s Kubernetes cluster on a group of Raspberry Pi nodes, from OS configuration to application deployment.

## Prerequisites

* **Ansible Controller**: A machine with Ansible installed to run these playbooks (e.g., your Mac Mini).
* **Raspberry Pi Nodes**: A set of Raspberry Pis with a fresh install of a compatible OS (e.g., Raspberry Pi OS).
* **SSH Access**: Passwordless SSH access from your Ansible controller to all Raspberry Pi nodes.
* **Python `kubernetes-client`**: The Helm and Kubernetes Ansible modules require this. Install it with `pip install kubernetes-client`.

## Inventory Setup

1.  Open the `hosts` file.
2.  Under the `[the_hive]` group, list the hostnames or IP addresses of your Raspberry Pi nodes. You can assign host names in the `/etc/hosts` file. The first node in the list will become the control plane (master).

    ```ini
    [the_hive]
    bee1
    bee2
    bee3
    bee4
    bee5
    ```
3.  Update the `ansible_user` variable in `[all:vars]` to match the username on your Raspberry Pi nodes.

## Installation and Setup

Follow these steps in order to provision your K3s cluster. Run all commands from your Ansible controller machine.

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

## Post-Installation

### Verify the Cluster

After the installation, you can verify that all nodes have joined the cluster. SSH into the master node (the first host in your inventory) and run the following command:

```bash
kubectl get nodes
```

You should see a list of all your nodes with a `Ready` status.

# Application Stack Deployment

### 1. Prepare Nodes for Longhorn

Installs `open-iscsi` and other dependencies required by Longhorn.

```bash
ansible-playbook -i hosts playbooks/setup_longhorn_playbook.yml
```

### 2. Deploy Core Application Stack

Uses Helm to deploy Longhorn, Prefect, Prometheus, and Grafana to the cluster.

```bash
ansible-playbook -i hosts playbooks/deploy_helm_stack_playbook.yml
```

### 3. Deploy n8n Workflow Automation

Applies the raw Kubernetes manifest to deploy n8n.

```bash
kubectl apply -f non-helm-deployments/n8n-deployment.yml
```

# Cluster Maintenance

## Perform a Safe Rolling Upgrade
This playbook safely cordons, drains, updates, and reboots one node at a time, ensuring cluster services remain available during OS-level upgrades.

```bash
ansible-playbook -i hosts playbooks/rolling_cluster_upgrade.yml
```
