# 🚀 StackTalosOpsEngine: Production-Grade Cloud Automation

This repository delivers a production-grade automation engine designed for deploying and managing a fully declarative cloud platform. Utilizing Infrastructure as Code (IaC) and a multi-layered GitOps workflow, the system establishes a robust, self-managing environment where OpenStack serves as the virtualized substrate, and a Talos-based cluster handles continuous operations.

The design targets repeatable production bring-up and lifecycle management, achieving a closed-loop system that spans from the virtualization host up to application delivery.

## ⚙️ Multi-Layer Architecture

This system is built upon two distinct, yet interconnected, declarative layers:
### 1. Infrastructure Layer (The Substrate)
This layer establishes the core virtualization and foundational cloud components:
* **Provisioning (Terraform/Libvirt):** Provisions all VMs (OpenStack controllers, computes, storage) and the initial **Talos Kubernetes nodes**.
* **Deployment (Ansible/OSA):** Deploys the full **OpenStack** cloud on its dedicated VMs and bootstraps the **Talos Management Cluster** on the Kubernetes nodes.
### 2. Management Layer (The Ops Engine)
The Talos Cluster acts as the single, declarative management plane for all tenant resources:
* **Orchestration (FluxCD/CAPI):** The cluster hosts FluxCD and Cluster API.
* **Control Flow:** CAPI continuously monitors Git and uses the OpenStack APIs to provision, manage, and reconcile all tenant workloads (VMs, networking, storage) on demand.
This workflow enforces a **GitOps-driven lifecycle model** where every component, from the base VMs to the deployed applications, is consistently controlled and managed from Git.

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
│  - Flux + Cluster API installed on Talos           │
└──────┬─────────────────────────────────────────────┘
       │ Flux reconciles Cluster API manifests
┌──────▼─────────────────────────────────────────────┐
│ OpenStack (Nova/Cinder/Neutron)                    │
│  - CAPI uses OpenStack APIs to create tenant VMs   │
│  - GitOps drives application delivery              │
└────────────────────────────────────────────────────┘
```

---

## Repository Layout

```
scripts/
  ├─ init.sh                   # Host prerequisite installer
  ├─ bootstrap-openstack.sh    # Terraform/Ansible wrapper for OpenStack stack
  └─ bootstrap-talos.sh        # Terraform/Ansible wrapper for Talos stack
terraform/
  ├─ openstack-libvirt/        # Libvirt module for OpenStack VMs
  └─ talos-cluster-bootstrap/  # Talos VM module
ansible/
  └─ roles/
       ├─ openstack/           # OSA orchestration (site + roles)
       └─ k8s-talos/           # Talos bootstrap and management addons (Flux, CAPI)
```

---

## Prerequisites

- Ubuntu/Debian host with hardware virtualization (KVM) and at least:
  - 128 GiB RAM, 48 vCPUs, >2 TB fast storage (default QCOW images are large)
  - Internet access for Ubuntu cloud images, OpenStack packages, Talos artifacts
- Ability to run commands with sudo/root privileges

Run the host preparation script once:

```bash
sudo ./scripts/init.sh
```

It updates apt, installs libvirt/qemu/OVMF/dnsmasq and supporting tooling (`talosctl`, `kubectl`, `helm`, Terraform, Ansible, jq), and configures `/etc/libvirt/qemu.conf` plus system services.

---

## Workflow

> **Order matters:** bootstrap OpenStack first so Talos has an infrastructure target to manage. Once OpenStack is healthy, bootstrap the Talos management cluster.

### 1. Provision and configure OpenStack

Use the production bootstrap helper rather than invoking Terraform manually:

```bash
./scripts/bootstrap-openstack.sh \
  --action apply \
  --var-file terraform.tfvars
```

Key flags:
- `--action <plan|apply|destroy>` — defaults to `apply`
- `--var-file` — alternate tfvars (relative or absolute)
- `--workspace` — optional Terraform workspace
- `--parallelism` — cap Terraform concurrency
- `--upgrade` — run `terraform init -upgrade`

Outputs from the script include:
- `ansible_inventory_file` — inventory path for manual OSA reruns
- `ssh_private_key_path` — SSH key used for the OpenStack VMs
- `{controller,compute,storage}_nodes` — network metadata for each VM

Validation snippet (controller node):

```bash
ssh -i terraform/openstack-libvirt/openstack_private_key.pem ubuntu@<controller_ip>
sudo -i
cd /opt/openstack-ansible
source playbooks/openrc
openstack compute service list
lxc-ls -f
```

### 2. Bootstrap the Talos management cluster

Once OpenStack is online, bring up the Talos management plane:

```bash
./scripts/bootstrap-talos.sh \
  --action apply \
  --var-file terraform.tfvars
```

The script mirrors the OpenStack helper (same flags) and invokes Terraform for `terraform/talos-cluster-bootstrap`. Terraform provisions Talos control-plane and worker VMs, generates the required inventories, and `ansible/roles/k8s-talos`:
- Installs Talos on every VM and bootstraps the control plane
- Joins workers and exposes kubeconfig via `talosctl`
- Installs Flux plus Cluster API configured for the OpenStack cloud so Git reconciliation drives tenant infrastructure

The helper prints summarized outputs for master/worker IPs and the generated Talos inventory (`terraform/talos-cluster-bootstrap/ansible_inventory.yaml`), making it easy to rerun Ansible or `talosctl` commands.

---

## Operations & Customization

- **Scaling OpenStack** – edit `terraform/openstack-libvirt/terraform.tfvars` (`*_count`, CPU/RAM/disk). Terraform hashes the Ansible content and tfvars, so reapplying reconciles changes automatically.
- **Network adjustments** – change `network_cidr` inside Terraform modules and update container/tunnel/storage CIDRs in `ansible/roles/openstack/site.yaml`.
- **OSA release** – set `osa_branch` within the OpenStack role to move between stable series.
- **Cinder backing disk** – override `cinder_lvm_device` if the extra disk differs from `/dev/vdb`.
- **Talos releases / Flux config** – tune variables under `terraform/talos-cluster-bootstrap` or defaults in `ansible/roles/k8s-talos` to select Talos versions, Flux Git sources, and Cluster API settings.
- **Manual reruns** – `ansible-playbook -i terraform/openstack-libvirt/ansible_inventory.yaml ansible/roles/openstack/site.yaml` for OpenStack, or reuse the generated Talos inventory with the k8s role.
- **Cleanup** – run `./scripts/bootstrap-<stack>.sh --action destroy` with the same tfvars/workspace settings to tear down each layer.

Expect roughly 30–60 minutes for the initial OpenStack deployment. The Talos bootstrap typically completes within minutes once the VMs are available. Re-running the bootstrap scripts is idempotent: Terraform reconciles infrastructure and the downstream Ansible roles/Flux sources ensure software state converges.

---

## Next Steps

1. Generate kubeconfig from Talos (`talosctl kubeconfig ...`) and verify Flux reconciliation status (`kubectl -n flux-system get kustomizations,sources`).
2. Author Cluster API manifests (`Cluster`, `OpenStackCluster`, `MachineDeployment`, `OpenStackMachineTemplate`) in your Flux source repository so Flux continuously deploys tenant clusters onto OpenStack.
3. Layer additional GitOps workloads or platform services on top of the Talos management cluster; Flux will fan out the changes through Cluster API into the OpenStack-backed infrastructure.

This engine gives you complete, declarative control—from the libvirt host through the OpenStack substrate to Kubernetes workloads governed by Flux—ready for production-oriented automation, testing, and iterative delivery.
