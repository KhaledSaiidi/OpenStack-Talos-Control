terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Storage pool
resource "libvirt_pool" "openstack_pool" {
  name = var.storage_pool
  type = "dir"
  target {
    path = var.storage_pool_path
  }
}

# Base OS image
resource "libvirt_volume" "ubuntu_qcow2" {
  name   = "ubuntu-22.04.qcow2"
  pool   = libvirt_pool.openstack_pool.name
  source = var.image_source
  format = "qcow2"
}

# Controller disks (base)
resource "libvirt_volume" "controller_disk" {
  count          = var.controller_count
  name           = "controller-${count.index + 1}-disk.qcow2"
  pool           = libvirt_pool.openstack_pool.name
  base_volume_id = libvirt_volume.ubuntu_qcow2.id
  format         = "qcow2"
}

# Compute disks (base)
resource "libvirt_volume" "compute_disk" {
  count          = var.compute_count
  name           = "compute-${count.index + 1}-disk.qcow2"
  pool           = libvirt_pool.openstack_pool.name
  base_volume_id = libvirt_volume.ubuntu_qcow2.id
  format         = "qcow2"
}

# Storage disks (base)
resource "libvirt_volume" "storage_disk" {
  count          = var.storage_count
  name           = "storage-${count.index + 1}-disk.qcow2"
  pool           = libvirt_pool.openstack_pool.name
  base_volume_id = libvirt_volume.ubuntu_qcow2.id
  format         = "qcow2"
}

# Network
resource "libvirt_network" "openstack_net" {
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

# SSH key pair
resource "tls_private_key" "openstack_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.openstack_key.private_key_openssh
  filename        = "${path.module}/openstack_private_key.pem"
  file_permission = "0600"
}

# Cloud-init disks
resource "libvirt_cloudinit_disk" "controller_init" {
  count     = var.controller_count
  name      = "controller-${count.index + 1}-init.iso"
  pool      = libvirt_pool.openstack_pool.name
  user_data = templatefile(local.cloud_init_path, {
    ssh_key  = tls_private_key.openstack_key.public_key_openssh
    hostname = "controller-${count.index + 1}"
  })
}

resource "libvirt_cloudinit_disk" "compute_init" {
  count     = var.compute_count
  name      = "compute-${count.index + 1}-init.iso"
  pool      = libvirt_pool.openstack_pool.name
  user_data = templatefile(local.cloud_init_path, {
    ssh_key  = tls_private_key.openstack_key.public_key_openssh
    hostname = "compute-${count.index + 1}"
  })
}

resource "libvirt_cloudinit_disk" "storage_init" {
  count     = var.storage_count
  name      = "storage-${count.index + 1}-init.iso"
  pool      = libvirt_pool.openstack_pool.name
  user_data = templatefile(local.cloud_init_path, {
    ssh_key  = tls_private_key.openstack_key.public_key_openssh
    hostname = "storage-${count.index + 1}"
  })
}

# Controller VMs
resource "libvirt_domain" "controller" {
  count  = var.controller_count
  name   = "controller-${count.index + 1}"
  vcpu   = var.controller_vcpus
  memory = var.controller_memory

  disk {
    volume_id = libvirt_volume.controller_disk[count.index].id
  }

  dynamic "disk" {
    for_each = range(var.controller_extra_disks)
    content {
      volume_id = libvirt_volume.controller_extra_disk[count.index * var.controller_extra_disks + disk.key].id
    }
  }

  network_interface {
    network_id     = libvirt_network.openstack_net.id
    mac            = format("52:54:00:00:00:%02x", 10 + count.index + 1) # starts at ...:11
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.controller_init[count.index].id

  cpu {
    mode = "host-passthrough"
  }
  graphics {
    type     = "vnc"
    autoport = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

# Compute VMs
resource "libvirt_domain" "compute" {
  count  = var.compute_count
  name   = "compute-${count.index + 1}"
  vcpu   = var.compute_vcpus
  memory = var.compute_memory

  disk {
    volume_id = libvirt_volume.compute_disk[count.index].id
  }

  dynamic "disk" {
    for_each = range(var.compute_extra_disks)
    content {
      volume_id = libvirt_volume.compute_extra_disk[count.index * var.compute_extra_disks + disk.key].id
    }
  }

  network_interface {
    network_id     = libvirt_network.openstack_net.id
    mac            = format("52:54:00:00:00:%02x", 20 + count.index + 1) # starts at ...:21
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.compute_init[count.index].id

  cpu {
    mode = "host-passthrough"
  }
  graphics {
    type     = "vnc"
    autoport = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

# Storage VMs
resource "libvirt_domain" "storage" {
  count  = var.storage_count
  name   = "storage-${count.index + 1}"
  vcpu   = var.storage_vcpus
  memory = var.storage_memory

  disk {
    volume_id = libvirt_volume.storage_disk[count.index].id
  }

  dynamic "disk" {
    for_each = range(var.storage_extra_disks)
    content {
      volume_id = libvirt_volume.storage_extra_disk[count.index * var.storage_extra_disks + disk.key].id
    }
  }

  network_interface {
    network_id     = libvirt_network.openstack_net.id
    mac            = format("52:54:00:00:00:%02x", 30 + count.index + 1) # starts at ...:31
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.storage_init[count.index].id

  cpu {
    mode = "host-passthrough"
  }
  graphics {
    type     = "vnc"
    autoport = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

# Extra disks per role (names show 1-based VM number)
resource "libvirt_volume" "controller_extra_disk" {
  count          = var.controller_count * var.controller_extra_disks
  name           = "controller-${floor(count.index / var.controller_extra_disks) + 1}-disk-${count.index % var.controller_extra_disks + 1}"
  pool           = libvirt_pool.openstack_pool.name
  size           = var.controller_extra_disk_size
  format         = "qcow2"
}

resource "libvirt_volume" "compute_extra_disk" {
  count          = var.compute_count * var.compute_extra_disks
  name           = "compute-${floor(count.index / var.compute_extra_disks) + 1}-disk-${count.index % var.compute_extra_disks + 1}"
  pool           = libvirt_pool.openstack_pool.name
  size           = var.compute_extra_disk_size
  format         = "qcow2"
}

resource "libvirt_volume" "storage_extra_disk" {
  count          = var.storage_count * var.storage_extra_disks
  name           = "storage-${floor(count.index / var.storage_extra_disks) + 1}-disk-${count.index % var.storage_extra_disks + 1}"
  pool           = libvirt_pool.openstack_pool.name
  size           = var.storage_extra_disk_size
  format         = "qcow2"
}

resource "random_password" "openstack_secret" {
  length  = 16
  special = false
}

resource "local_file" "ansible_inventory" {
  content         = local.ansible_inventory
  filename        = "${path.module}/ansible_inventory.yaml"
  file_permission = "0644"
}

resource "null_resource" "ansible_provision" {
  depends_on = [
    libvirt_domain.controller,
    libvirt_domain.compute,
    libvirt_domain.storage,
    random_password.openstack_secret,
    local_file.private_key,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = <<EOF
      PYTHONUNBUFFERED=1 ansible-playbook \
        -i ${local_file.ansible_inventory.filename} \
        ../../ansible/roles/openstack/site.yaml \
        || exit 1
    EOF
  }
}
