# K3s Raspberry Pi Cluster Setup with Ansible

This repository contains Ansible playbooks to automate the setup of a K3s Kubernetes cluster on a group of Raspberry Pi nodes.

## Prerequisites

*   **Ansible Controller**: You need a machine with Ansible installed to run these playbooks.
*   **Raspberry Pi Nodes**: A set of Raspberry Pis with a fresh install of a compatible OS (e.g., Raspberry Pi OS).
*   **SSH Access**: Ensure you have passwordless SSH access from your Ansible controller to all Raspberry Pi nodes.

## Inventory Setup

1.  Open the `hosts` file.
2.  Under the `[the_hive]` group, list the hostnames or IP addresses of your Raspberry Pi nodes. You can assign host names in the /etc/hosts file.

    ```ini
    [the_hive]
    bee1
    bee2
    bee3
    bee4
    bee5
    ```
3.  Update the `ansible_user` variable in `[all:vars]` to match the username on your Raspberry Pi nodes.

## Installation Steps

Follow these steps in order to provision your K3s cluster.

### 1. Update and Reboot Nodes

First, ensure all your Raspberry Pi nodes are up-to-date. This playbook will update the `apt` package cache, upgrade all packages, and reboot the nodes.

```bash
ansible-playbook update_playbook.yml
```

### 2. Enable Cgroups

For Kubernetes to function correctly, you need to enable control groups (cgroups) on all nodes. This playbook modifies the boot configuration and reboots the nodes to apply the changes.

```bash
ansible-playbook enable_cgroups_playbook.yml
```

### 3. (Optional) Mount External Storage

If you plan to use external storage with your cluster, this playbook will partition, format, and mount a USB drive on all nodes.

```bash
ansible-playbook mount_external_storage_playbook.yml
```

### 4. Install K3s

This is the final step to install the K3s cluster. The playbook will:
1.  Install the K3s server on the first node in your inventory (`the_hive[0]`).
2.  Retrieve the join token from the master node.
3.  Install the K3s agent on the remaining worker nodes, connecting them to the master.

```bash
ansible-playbook k3s_playbook.yml
```

After the playbook finishes, your K3s cluster will be up and running. You can SSH into the master node and use `kubectl` to manage your cluster.
