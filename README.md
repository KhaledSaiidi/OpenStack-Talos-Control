## OpenStack-Ansible Lab Automation

This repository wires Terraform, libvirt and Ansible together to provision a three-tier OpenStack control plane (controllers, computes, storage) and then deploy a full OpenStack-Ansible (OSA) environment on top of those VMs. Talos/Kubernetes automation lives in parallel, but this document focuses on the OpenStack stack.

### High-level flow

1. **Terraform (`terraform/openstack-libvirt`)**  
   - Creates a libvirt storage pool and clones an Ubuntu 22.04 cloud image for every controller, compute and storage VM.  
   - Attaches an additional data disk per role (e.g. for Cinder LVM) and grows the root disks (controllers 150 GiB, computes 120 GiB, storage 100 GiB by default).  
   - Builds an isolated libvirt network and cloud-init metadata that enables the `ubuntu` user with the generated SSH key.  
   - Writes an Ansible inventory that groups the VMs into `controllers`, `computes` and `storage`.
2. **Ansible (`ansible/roles/openstack/site.yaml`)** – kicked off automatically from Terraform’s `null_resource`:
   - Waits for SSH + `cloud-init` completion on every node.
   - Installs base packages (git, python3, qemu-guest-agent, LVM tools, etc.) everywhere and prepares the `cinder-volumes` VG on storage nodes.
   - On the first controller, clones OSA `stable/epoxy`, renders `openstack_user_config.yml`/`user_variables.yml` from the Terraform inventory, generates secrets, and runs the standard `setup-hosts`, `setup-infrastructure`, and `setup-openstack` playbooks.

The net result is a production-style, containerised OpenStack control plane managed by OSA instead of DevStack.

### Prerequisites

- Host with KVM + libvirt (`qemu:///system`) and enough resources (expect ~64 GiB RAM and 24+ vCPUs for the default counts).
- Terraform ≥ 1.5 and Ansible ≥ 2.14 available on the management workstation.
- Internet access from the controller VM to clone packages and container images.

Optional but recommended: `virt-manager` / `virsh` CLI to inspect VMs, and the `netaddr` python package locally if you inspect the rendered configs.

### Repository layout

```
terraform/openstack-libvirt   # libvirt/KVM infrastructure for OpenStack nodes
ansible/roles/openstack       # Ansible plays + roles deploying OpenStack-Ansible
scripts/                      # Helper scripts (unchanged Talos helpers)
```

### Terraform usage

```bash
cd terraform/openstack-libvirt
terraform init
terraform apply -var-file=terraform.tfvars
```

Key variables live in `terraform.tfvars`. Adjust counts, CPU/RAM, disk sizes or network CIDRs there to suit your lab. Root disk sizes are now explicit (`*_root_disk_size`) so you can safely grow them for controller and compute services.

Useful outputs after `apply`:

- `controller_nodes`, `compute_nodes`, `storage_nodes` – IP/MAC info per VM.
- `ansible_inventory_file` – path to the generated inventory YAML.
- `ssh_private_key_path` – private key used by Ansible/SSH (sensitive).

Destroying everything:

```bash
terraform destroy -var-file=terraform.tfvars
```

### What the Ansible playbook does

`ansible/roles/openstack/site.yaml` orchestrates three plays:

1. **Wait for SSH/cloud-init** – ensures every VM is reachable before configuration.  
2. **Host preparation** – installs dependencies, enables `qemu-guest-agent`, and on storage nodes provisions `/dev/vdb` into a `cinder-volumes` VG (tweak `cinder_lvm_device` if your extra disk path differs).  
3. **OSA bootstrap** – runs only on `controllers[0]`:
   - Clones OSA (`stable/epoxy`) into `/opt/openstack-ansible` and bootstraps its virtualenv.
   - Renders:
     - `openstack_user_config.yml` with deterministic management/tunnel/storage subnets (`172.29.{236,240,244}.0/22`), provider networks, HAProxy VIPs, and all host group mappings.
     - `user_variables.yml` enabling OVN networking, `kvm` hypervisors and a simple LVM Cinder backend bound to the first storage node’s storage-network IP.
   - Generates service passwords with `pw-token-gen.py`.
   - Runs `openstack-ansible setup-hosts.yml`, `setup-infrastructure.yml`, `setup-openstack.yml`.

To re-run the deployment manually (e.g. after editing templates):

```bash
ansible-playbook -i terraform/openstack-libvirt/ansible_inventory.yaml \
  ansible/roles/openstack/site.yaml
```

### Post-deploy verification

1. SSH to the first controller (inventory output shows IP/host):
   ```bash
   ssh -i terraform/openstack-libvirt/openstack_private_key.pem ubuntu@<controller_ip>
   sudo -i
   cd /opt/openstack-ansible
   source playbooks/openrc
   openstack compute service list
   ```
2. Inspect running containers/hosts via `lxc-ls -f` (OSA uses LXC by default on Epoxy).
3. If something fails mid-run, you can restart from `/opt/openstack-ansible/playbooks` by invoking the specific `openstack-ansible <playbook>.yml` command again.

### Customisation tips

- **Scaling**: bump `controller_count`, `compute_count`, `storage_count` in `terraform.tfvars`. The inventory/template logic automatically assigns deterministic management, tunnel and storage IPs per host.  
- **Networks**: change `cidr_container`, `cidr_tunnel`, `cidr_storage` and the corresponding `*_octets` values in `ansible/roles/openstack/site.yaml` if the default 172.29.0.0/22 ranges conflict with other labs.  
- **OSA release**: set `osa_branch` in the same play to track another stable series.  
- **Cinder backend disk**: override `cinder_lvm_device` if libvirt maps the extra disk somewhere other than `/dev/vdb`.

### Operational notes

- Terraform will re-run the entire Ansible deployment if any infrastructure changes (or if you call `terraform apply` again). Expect a lengthy run (30–60 minutes) while `setup-openstack.yml` configures every service.  
- Keep an eye on host capacity: the defaults allocate ~24 vCPUs / 72 GiB RAM total plus sizable QCOW2 disks. Adjust downward only if you understand the trade-offs (OSA containers are memory hungry).  
- Outputs expose the inventory path and SSH key so you can integrate with other tooling (e.g., additional Ansible plays or monitoring agents).

This end-to-end workflow now yields a production-style OpenStack-Ansible deployment instead of a DevStack sandbox, while remaining reproducible via Terraform.
