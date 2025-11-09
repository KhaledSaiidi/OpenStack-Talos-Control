## OpenStack + Talos GitOps Lab

This repository automates a two-layer lab environment:

1. **Infrastructure layer** – Terraform (via Libvirt) provisions the complete virtualization stack, including OpenStack controller, compute, and storage VMs, as well as Talos-based Kubernetes nodes. Ansible then deploys OpenStack using OpenStack-Ansible (OSA) on the dedicated OpenStack VMs and bootstraps a Talos Kubernetes cluster on the remaining Talos nodes.
2. **Management layer** – The Talos cluster serves as the management plane, where Argo CD continuously reconciles Cluster API (CAPI) resources to instantiate tenant workloads within the freshly deployed OpenStack cloud. This creates a self-managing, closed-loop GitOps workflow that spans from bare metal provisioning to application deployment.

To establish a fully automated, GitOps-driven lifecycle management model where OpenStack provides the virtualized infrastructure substrate, and Talos + Argo CD orchestrate the higher-level services and workloads on top.

---

## Architecture Overview

```
┌──────────────┐
│ Bare-metal   │  scripts/init.sh installs libvirt/qemu/terraform/ansible
└──────┬───────┘
       │ Terraform + Ansible
┌──────▼─────────────────────────────────────────────┐
│ terraform/openstack-libvirt                        │
│  - storage pool + NAT network                      │
│  - controller/compute/storage VMs                  │
│  - cloud-init + Ansible inventory                  │
└──────┬─────────────────────────────────────────────┘
       │ kicks off ansible/roles/openstack/site.yaml
┌──────▼─────────────────────────────────────────────┐
│ OpenStack-Ansible deployment (controller[0])       │
│  - OSA stable/epoxy                                │
│  - OVN networking, LVM Cinder backend              │
│  - Full OpenStack control plane                    │
└──────┬─────────────────────────────────────────────┘
       │
┌──────▼─────────────────────────────────────────────┐
│ terraform/talos-cluster-bootstrap                  │
│  - Talos control-plane + worker VMs                │
│  - ansible/roles/k8s-talos bootstraps the cluster  │
│  - Argo CD + Cluster API installed on Talos        │
└──────┬─────────────────────────────────────────────┘
       │ Argo CD reconciles Cluster API manifests
┌──────▼─────────────────────────────────────────────┐
│ OpenStack (Nova/Cinder/Neutron)                    │
│  - CAPI uses OpenStack APIs to create tenant VMs   │
│  - GitOps drives application delivery              │
└────────────────────────────────────────────────────┘
```

---

## Repository Layout

```
scripts/                         # Host bootstrap helpers (init.sh)
terraform/
  ├─ openstack-libvirt/          # Libvirt module for OpenStack VMs
  └─ talos-cluster-bootstrap/    # Talos VM module
ansible/
  └─ roles/
       ├─ openstack/             # OSA orchestration (site + roles)
       └─ k8s-talos/             # Talos bootstrap and addons
```

---

## Prerequisites

- Ubuntu/Debian host with hardware virtualization (KVM) and at least:
  - 128 GiB RAM, 48 vCPUs, >2 TB fast storage (defaults allocate large QCOW images)
  - Internet access for Ubuntu cloud images, OpenStack packages, Talos artifacts
- Ability to run commands with sudo/root privileges

Run `scripts/init.sh` once as root to install libvirt/qemu, enable services, and place `talosctl`, `kubectl`, `helm`, `argocd`, Terraform, and Ansible.

---

## Workflow

### 1. Host preparation

```bash
sudo ./scripts/init.sh
```

The script updates apt, installs libvirt/qemu/OVMF/dnsmasq, enables services, configures `/etc/libvirt/qemu.conf` for nested virtualization, and installs all required CLIs.

### 2. Provision and configure OpenStack

```bash
cd terraform/openstack-libvirt
terraform init
terraform apply -var-file=terraform.tfvars
```

What Terraform + Ansible deliver:
- Libvirt storage pool and NAT network
- Ubuntu-based controller/compute/storage VMs sized per OSA requirements (16 vCPU & 48 GiB RAM controllers, 16 vCPU & 32 GiB computes, 8 vCPU & 32 GiB storage, with large root/extra disks for MariaDB/logs/Cinder)
- Generated SSH key + cloud-init configuration for the `ubuntu` user
- Auto-generated Ansible inventory and secrets
- Execution of `ansible/roles/openstack/site.yaml`, which:
  1. Waits for SSH/cloud-init
  2. Installs base packages and prepares the `cinder-volumes` VG (`lvg` ensures idempotence)
  3. Clones OpenStack-Ansible `stable/epoxy`, renders `openstack_user_config.yml` and `user_variables.yml`, generates passwords, then runs `setup-hosts.yml`, `setup-infrastructure.yml`, and `setup-openstack.yml`

Useful Terraform outputs:
- `ansible_inventory_file` – inventory path for manual reruns
- `ssh_private_key_path` – private key used for the VMs
- `{controller,compute,storage}_nodes` – VM IP/MAC metadata

Verification (on controller):

```bash
ssh -i terraform/openstack-libvirt/openstack_private_key.pem ubuntu@<controller_ip>
sudo -i
cd /opt/openstack-ansible
source playbooks/openrc
openstack compute service list
lxc-ls -f
```

### 3. Bootstrap the Talos management cluster

```bash
cd terraform/talos-cluster-bootstrap
terraform init
terraform apply -var-file=terraform.tfvars
```

The Talos module mirrors the OpenStack pattern: Terraform stands up the control-plane/worker VMs, builds an inventory, then the `k8s-talos` role:
- Installs Talos on each VM
- Bootstraps the Talos control plane and joins workers
- Installs Argo CD plus the Cluster API components configured for the OpenStack cloud

Once Argo CD is up, log in (password output from the role) and point it at the Git repo containing Cluster API manifests. CAPI will use the OpenStack credentials to provision tenant clusters and workloads on demand.

---

## Operations & Customization

- **Scaling OpenStack** – edit `terraform/openstack-libvirt/terraform.tfvars` (`*_count`, CPU/RAM/disk). Terraform hashes the Ansible role content and tfvars, so changes automatically trigger a redeploy.
- **Network adjustments** – change `network_cidr` in Terraform and update the container/tunnel/storage CIDRs in `ansible/roles/openstack/site.yaml`.
- **OSA release** – set `osa_branch` within the site play to follow another stable series.
- **Cinder backing disk** – override `cinder_lvm_device` if the extra disk is not `/dev/vdb`.
- **Talos versions** – tune variables under `terraform/talos-cluster-bootstrap` or defaults in `ansible/roles/k8s-talos`.
- **Manual reruns** – `ansible-playbook -i terraform/openstack-libvirt/ansible_inventory.yaml ansible/roles/openstack/site.yaml`.
- **Cleanup** – run `terraform destroy -var-file=terraform.tfvars` in each module to remove resources.

Expect ~30–60 minutes for the initial OpenStack deployment; Talos typically finishes within minutes once VMs are running. Reapplying Terraform reconciles both infrastructure and software layers, keeping the lab reproducible.

---

## Next Steps

1. Configure kubectl access to the Talos cluster (`talosctl kubeconfig ...`) and install Argo CD.
2. Author Cluster API manifests (`Cluster`, `OpenStackCluster`, `MachineDeployment`, `OpenStackMachineTemplate`) in Git and let Argo CD reconcile them.
3. Observe Cluster API provisioning Nova instances inside OpenStack, then deploy applications via GitOps workflows layered on those tenant clusters.

With this stack you control every layer—from the libvirt host through OpenStack infrastructure to application workloads—using declarative artifacts. Use it to test upgrades, validate new OpenStack services, or practice GitOps patterns before promoting changes to production environments.
