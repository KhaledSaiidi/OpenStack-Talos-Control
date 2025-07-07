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

# Download and prepare the image only when version changes
resource "null_resource" "talos_image" {
  triggers = { talos_version = var.talos_gen_version }

  provisioner "local-exec" {
    command = <<-EOF
      bash -c '
        set -euo pipefail
        mkdir -p "${local.raw_dir}"

        # Download if not present
        if [ ! -f "${local.raw_dir}/raw.zst" ]; then
          echo "Downloading Talos raw.zst ..."
          curl -L -o "${local.raw_dir}/raw.zst" "${local.image_url}"
        fi

        # Decompress
        if [ ! -f "${local.raw_file}" ]; then
          echo "Decompressing ..."
          unzstd -f "${local.raw_dir}/raw.zst" -o "${local.raw_file}"
        fi

        # Convert to qcow2 (optional but recommended)
        if [ ! -f "${local.qcow_file}" ]; then
          echo "Converting to qcow2 ..."
          qemu-img convert -f raw -O qcow2 "${local.raw_file}" "${local.qcow_file}"
        fi
      '
    EOF
  }
}

# Talos image
resource "libvirt_volume" "talos_base" {
  depends_on = [null_resource.talos_image]

  name   = "talos-${var.talos_gen_version}-base.qcow2"
  pool   = libvirt_pool.k8s_pool.name
  source = local.qcow_file
  format = "qcow2"
}

resource "libvirt_volume" "master_disk" {
  count          = var.master_count
  name           = "master-${count.index + 1}-disk.qcow2"
  pool           = libvirt_pool.k8s_pool.name
  base_volume_id = libvirt_volume.talos_base.id
  format         = "qcow2"
}

# Individual disks for worker nodes
resource "libvirt_volume" "worker_disk" {
  count          = var.worker_count
  name           = "worker-${count.index + 1}-disk.qcow2"
  pool           = libvirt_pool.k8s_pool.name
  base_volume_id = libvirt_volume.talos_base.id
  format         = "qcow2"
}

# Additional disks for master nodes
resource "libvirt_volume" "master_extra_disk" {
  count          = var.master_count * var.master_extra_disks
  name           = "master-${floor(count.index / var.master_extra_disks) + 1}-disk-${count.index % var.master_extra_disks + 1}"
  pool           = libvirt_pool.k8s_pool.name
  size           = var.master_extra_disk_size
  format         = "qcow2"
}

# Additional disks for worker nodes
resource "libvirt_volume" "worker_extra_disk" {
  count          = var.worker_count * var.worker_extra_disks
  name           = "worker-${floor(count.index / var.worker_extra_disks) + 1}-disk-${count.index % var.worker_extra_disks + 1}"
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
  name   = "master-${count.index + 1}"
  vcpu   = var.master_vcpus
  memory = var.master_memory

  # Writable system disk
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


  cpu {
    mode = "host-passthrough"
  }
}

# worker nodes
resource "libvirt_domain" "worker" {
  count  = var.worker_count
  name   = "worker-${count.index + 1}"
  vcpu   = var.worker_vcpus
  memory = var.worker_memory

  # Writable system disk
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

  cpu {
    mode = "host-passthrough"
  }
}

resource "null_resource" "talos_gen" {
  depends_on = [libvirt_domain.master]
  triggers = {
    cluster_name    = var.cluster_name
    talos_version   = var.talos_gen_version
    k8s_version     = var.k8s_version
    master_0_ip     = libvirt_domain.master[0].network_interface.0.addresses[0]
  }

  provisioner "local-exec" {
    command = <<-EOF
      bash -c '
        set -euo pipefail

        OUT_DIR=${path.module}/../../ansible/roles/k8s-talos/talos-outputs
        mkdir -p "$OUT_DIR"

        echo "Waiting for Talos plaintext API on master-0 (${self.triggers.master_0_ip}:50000)..."
        timeout 300 bash -c "until nc -zv ${self.triggers.master_0_ip} 50000; do sleep 5; done"

        echo "Generating Talos configs with API endpoint https://${self.triggers.master_0_ip}:6443"
        talosctl gen config "${self.triggers.cluster_name}" https://${self.triggers.master_0_ip}:6443 \
          --kubernetes-version ${self.triggers.k8s_version} \
          --output-dir "$OUT_DIR"
        echo "Talos configs generated at $OUT_DIR"
      '
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
