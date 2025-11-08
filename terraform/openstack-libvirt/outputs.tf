output "controller_nodes" {
  description = "Details of controller nodes"
  value = [
    for i, vm in libvirt_domain.controller : {
      hostname = "controller-${i}"
      ip       = vm.network_interface[0].addresses[0]
      mac      = vm.network_interface[0].mac
      disks    = concat([libvirt_volume.ubuntu_qcow2.id], [for j in range(var.controller_extra_disks) : libvirt_volume.controller_extra_disk[i * var.controller_extra_disks + j].id])
    }
  ]
}

output "compute_nodes" {
  description = "Details of compute nodes"
  value = [
    for i, vm in libvirt_domain.compute : {
      hostname = "compute-${i}"
      ip       = vm.network_interface[0].addresses[0]
      mac      = vm.network_interface[0].mac
      disks    = concat([libvirt_volume.ubuntu_qcow2.id], [for j in range(var.compute_extra_disks) : libvirt_volume.compute_extra_disk[i * var.compute_extra_disks + j].id])
    }
  ]
}

output "storage_nodes" {
  description = "Details of storage nodes"
  value = [
    for i, vm in libvirt_domain.storage : {
      hostname = "storage-${i}"
      ip       = vm.network_interface[0].addresses[0]
      mac      = vm.network_interface[0].mac
      disks    = concat([libvirt_volume.ubuntu_qcow2.id], [for j in range(var.storage_extra_disks) : libvirt_volume.storage_extra_disk[i * var.storage_extra_disks + j].id])
    }
  ]
}

output "network_name" {
  description = "Name of the created libvirt network"
  value       = libvirt_network.openstack_net.name
}

output "ssh_public_key" {
  description = "SSH public key for node access"
  value       = tls_private_key.openstack_key.public_key_openssh
}

output "ansible_inventory" {
  description = "Ansible inventory for OpenStack deployment"
  value = {
    controllers = [
      for i, vm in libvirt_domain.controller : {
        ansible_host = vm.network_interface[0].addresses[0]
        ansible_user = "ubuntu"
        hostname     = "controller-${i}"
      }
    ]
    computes = [
      for i, vm in libvirt_domain.compute : {
        ansible_host = vm.network_interface[0].addresses[0]
        ansible_user = "ubuntu"
        hostname     = "compute-${i}"
      }
    ]
    storage = [
      for i, vm in libvirt_domain.storage : {
        ansible_host = vm.network_interface[0].addresses[0]
        ansible_user = "ubuntu"
        hostname     = "storage-${i}"
      }
    ]
  }
}

output "ansible_inventory_file" {
  description = "Rendered inventory file path passed to Ansible"
  value       = local_file.ansible_inventory.filename
}

output "ssh_private_key_path" {
  description = "Private key generated for the OpenStack nodes"
  value       = local_file.private_key.filename
  sensitive   = true
}
