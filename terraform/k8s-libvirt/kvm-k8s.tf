terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Storage pool
resource "libvirt_pool" "k8s_pool" {
  name = var.storage_pool
  type = "dir"
  target {
    path = var.storage_pool_path
  }
}

# Base OS image
resource "libvirt_volume" "talos_iso" {
  name   = "talos-v1.10.5-metal.iso"
  pool   = libvirt_pool.k8s_pool.name
  source = var.image_source
  format = "raw"
}

resource "libvirt_volume" "master_disk" {
  count          = var.master_count
  name           = "master-${count.index}-disk.qcow2"
  pool           = libvirt_pool.k8s_pool.name
  size           = var.master_disk_size
  format         = "qcow2"
}

# Individual disks for worker nodes
resource "libvirt_volume" "worker_disk" {
  count          = var.worker_count
  name           = "worker-${count.index}-disk.qcow2"
  pool           = libvirt_pool.k8s_pool.name
  size           = var.worker_disk_size
  format         = "qcow2"
}

# Additional disks for master nodes
resource "libvirt_volume" "master_extra_disk" {
  count          = var.master_count * var.master_extra_disks
  name           = "master-${floor(count.index / var.master_extra_disks)}-disk-${count.index % var.master_extra_disks + 1}"
  pool           = libvirt_pool.k8s_pool.name
  size           = var.master_extra_disk_size
  format         = "qcow2"
}

# Additional disks for worker nodes
resource "libvirt_volume" "worker_extra_disk" {
  count          = var.worker_count * var.worker_extra_disks
  name           = "worker-${floor(count.index / var.worker_extra_disks)}-disk-${count.index % var.worker_extra_disks + 1}"
  pool           = libvirt_pool.k8s_pool.name
  size           = var.worker_extra_disk_size
  format         = "qcow2"
}

# Network
resource "libvirt_network" "k8s_net" {
  name      = var.network_name
  mode      = var.network_mode
  bridge    = var.network_mode == "bridge" ? var.network_bridge : null
  addresses = var.network_mode == "nat" ? [var.network_cidr] : []
  dhcp {
    enabled = var.network_mode == "nat"
  }
  dns {
    enabled = true
  }
}

# master nodes
resource "libvirt_domain" "master" {
  count  = var.master_count
  name   = "master-${count.index}"
  vcpu   = var.master_vcpus
  memory = var.master_memory

  # Writable system disk
  disk {
    volume_id = libvirt_volume.master_disk[count.index].id
    boot_order = 2
  }
  # Shared read-only Talos ISO
  disk { 
    volume_id = libvirt_volume.talos_iso.id
    device     = "cdrom"
    read_only  = true
    boot_order = 1
  }

  dynamic "disk" {
    for_each = range(var.master_extra_disks)
    content {
      volume_id = libvirt_volume.master_extra_disk[count.index * var.master_extra_disks + disk.key].id
    }
  }

  network_interface {
    network_id     = libvirt_network.k8s_net.id
    mac            = format("52:54:00:00:00:%02x", 10 + count.index)
    wait_for_lease = true
  }


  cpu {
    mode = "host-passthrough"
  }
}

# worker nodes
resource "libvirt_domain" "worker" {
  count  = var.worker_count
  name   = "worker-${count.index}"
  vcpu   = var.worker_vcpus
  memory = var.worker_memory

  # Writable system disk
  disk {
    volume_id = libvirt_volume.worker_disk[count.index].id
    boot_order = 2
  }
  # Shared read-only Talos ISO
  disk { 
    volume_id = libvirt_volume.talos_iso.id
    device     = "cdrom"
    read_only  = true
    boot_order = 1
  }

  dynamic "disk" {
    for_each = range(var.worker_extra_disks)
    content {
      volume_id = libvirt_volume.worker_extra_disk[count.index * var.worker_extra_disks + disk.key].id
    }
  }

  network_interface {
    network_id     = libvirt_network.k8s_net.id
    mac            = format("52:54:00:00:00:%02x", 20 + count.index)
    wait_for_lease = true
  }

  cpu {
    mode = "host-passthrough"
  }
}
resource "null_resource" "talos_gen" {
  triggers = {
    cluster = var.cluster_name
    talos_version  = var.talos_gen_version
    k8s_version    = var.k8s_version
  }

  provisioner "local-exec" {
    command = <<-EOF
      set -euo pipefail
      OUT_DIR=${path.module}/../../ansible/roles/k8s-talos/talos-outputs
      mkdir -p "$OUT_DIR"
      talosctl gen config "${self.triggers.cluster}" https://0.0.0.0:6443 \
        --with-kubelet=true \
        --kubernetes-version ${self.triggers.k8s_version} \
        --output-dir "$OUT_DIR"
    EOF
  }
}

resource "local_file" "ansible_inventory" {
  content         = local.ansible_inventory
  filename        = "${path.module}/ansible_inventory.yaml"
  file_permission = "0644"
}

resource  "null_resource" "ansible_provision" {
  depends_on = [
    null_resource.talos_gen,
    libvirt_domain.master,
    libvirt_domain.worker,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = <<EOF
      PYTHONUNBUFFERED=1 ansible-playbook \
        -i ${local_file.ansible_inventory.filename} \
        ../../ansible/roles/k8s-talos/talos.yaml \
        || exit 1
    EOF
  }
}
