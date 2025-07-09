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

resource "libvirt_pool" "k8s_pool" {
  name = var.storage_pool
  type = "dir"
  target {
    path = var.storage_pool_path
  }
}

resource "null_resource" "talos_iso" {
  triggers = { talos_version = var.talos_gen_version }

  provisioner "local-exec" {
    command = <<-EOF
      bash -c '
        set -euo pipefail
        mkdir -p "${local.iso_dir}"
        if [ ! -f "${local.iso_file}" ]; then
          echo "Downloading Talos ISO..."
          sudo curl -L -o "${local.iso_file}" "${local.iso_url}"
        fi
      '
    EOF
  }
}


resource "null_resource" "master_iso" {
  count      = var.master_count
  depends_on = [null_resource.talos_iso]

  provisioner "local-exec" {
    command = <<-EOT
      sudo cp "${local.iso_file}" "${var.storage_pool_path}/talos-${var.talos_gen_version}-master-${count.index + 1}.iso"
    EOT
  }
}

resource "null_resource" "worker_iso" {
  count      = var.worker_count
  depends_on = [null_resource.talos_iso]

  provisioner "local-exec" {
    command = <<-EOT
     sudo cp "${local.iso_file}" "${var.storage_pool_path}/talos-${var.talos_gen_version}-worker-${count.index + 1}.iso"
    EOT
  }
}

# Clean up per-VM ISO copies on destroy
resource "null_resource" "cleanup_iso" {
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      sudo rm -f /var/lib/libvirt/images/talos-*-master-*.iso
      sudo rm -f /var/lib/libvirt/images/talos-*-worker-*.iso
    EOT
  }
}


resource "null_resource" "refresh_libvirt_pool" {
  depends_on = [
    null_resource.master_iso,
    null_resource.worker_iso
  ]

  provisioner "local-exec" {
    command = <<EOT
      sudo virsh pool-refresh ${libvirt_pool.k8s_pool.name}
    EOT
  }
}

resource "libvirt_volume" "master_disk" {
  count  = var.master_count
  name   = "master-${count.index + 1}-disk.qcow2"
  pool   = libvirt_pool.k8s_pool.name
  size   = var.master_root_disk_size
  format = "qcow2"
}

resource "libvirt_volume" "worker_disk" {
  count  = var.worker_count
  name   = "worker-${count.index + 1}-disk.qcow2"
  pool   = libvirt_pool.k8s_pool.name
  size   = var.worker_root_disk_size
  format = "qcow2"
}

resource "libvirt_volume" "master_extra_disk" {
  count  = var.master_count * var.master_extra_disks
  name   = "master-${floor(count.index / var.master_extra_disks) + 1}-extra-disk-${count.index % var.master_extra_disks + 1}"
  pool   = libvirt_pool.k8s_pool.name
  size   = var.master_extra_disk_size
  format = "qcow2"
}

resource "libvirt_volume" "worker_extra_disk" {
  count  = var.worker_count * var.worker_extra_disks
  name   = "worker-${floor(count.index / var.worker_extra_disks) + 1}-extra-disk-${count.index % var.worker_extra_disks + 1}"
  pool   = libvirt_pool.k8s_pool.name
  size   = var.worker_extra_disk_size
  format = "qcow2"
}

# Libvirt network
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

# Masters
resource "libvirt_domain" "master" {
  depends_on = [null_resource.refresh_libvirt_pool]
  count  = var.master_count
  name   = "master-${count.index + 1}"
  vcpu   = var.master_vcpus
  memory = var.master_memory

  # Attach per-VM ISO
  disk {
    file = "${var.storage_pool_path}/talos-${var.talos_gen_version}-master-${count.index + 1}.iso"
  }

  disk {
    volume_id = libvirt_volume.master_disk[count.index].id
  }

  dynamic "disk" {
    for_each = range(var.master_extra_disks)
    content {
      volume_id = libvirt_volume.master_extra_disk[count.index * var.master_extra_disks + disk.key].id
    }
  }

  network_interface {
    network_id     = libvirt_network.k8s_net.id
    mac            = format("52:54:00:00:00:%02x", 10 + count.index + 1)
    wait_for_lease = true
  }

  boot_device {
    dev = ["cdrom", "hd"]
  }

  cpu {
    mode = "host-passthrough"
  }
}

# Workers
resource "libvirt_domain" "worker" {
  depends_on = [null_resource.refresh_libvirt_pool]
  count  = var.worker_count
  name   = "worker-${count.index + 1}"
  vcpu   = var.worker_vcpus
  memory = var.worker_memory

  # Attach per-VM ISO
  disk {
    file = "${var.storage_pool_path}/talos-${var.talos_gen_version}-worker-${count.index + 1}.iso"
  }

  disk {
    volume_id = libvirt_volume.worker_disk[count.index].id
  }

  dynamic "disk" {
    for_each = range(var.worker_extra_disks)
    content {
      volume_id = libvirt_volume.worker_extra_disk[count.index * var.worker_extra_disks + disk.key].id
    }
  }

  network_interface {
    network_id     = libvirt_network.k8s_net.id
    mac            = format("52:54:00:00:00:%02x", 20 + count.index + 1)
    wait_for_lease = true
  }

  boot_device {
    dev = ["cdrom", "hd"]
  }

  cpu {
    mode = "host-passthrough"
  }
}

resource "local_file" "ansible_inventory" {
  content         = local.ansible_inventory
  filename        = "${path.module}/ansible_inventory.yaml"
  file_permission = "0644"
}

resource "null_resource" "ansible_provision" {
  depends_on = [
    libvirt_domain.master,
    libvirt_domain.worker,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = <<EOF
      PYTHONUNBUFFERED=1 ansible-playbook \
        -i ${local_file.ansible_inventory.filename} \
        ../../ansible/roles/k8s-talos/site.yaml \
        || exit 1
    EOF
  }
}
