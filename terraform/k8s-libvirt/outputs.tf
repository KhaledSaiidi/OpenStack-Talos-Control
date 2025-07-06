output "master_nodes" {
  description = "Details of master nodes"
  value = [
    for i, vm in libvirt_domain.master : {
      hostname = "master-${i}"
      ip       = vm.network_interface[0].addresses[0]
      mac      = vm.network_interface[0].mac
      disks    = concat(
        [libvirt_volume.master_disk[i].id],
        [for j in range(var.master_extra_disks) :
           libvirt_volume.master_extra_disk[
             i * var.master_extra_disks + j
           ].id]
      )
    }
  ]
}

output "worker_nodes" {
  description = "Details of worker nodes"
  value = [
    for i, vm in libvirt_domain.worker : {
      hostname = "worker-${i}"
      ip       = vm.network_interface[0].addresses[0]
      mac      = vm.network_interface[0].mac
      disks    = concat(
        [libvirt_volume.worker_disk[i].id],
        [for j in range(var.worker_extra_disks) :
           libvirt_volume.worker_extra_disk[
             i * var.worker_extra_disks + j
           ].id]
      )
    }
  ]
}

output "network_name" {
  description = "Name of the created libvirt network"
  value       = libvirt_network.k8s_net.name
}

output "ansible_inventory" {
  description = "Ansible inventory for K8S deployment"
  value = {
    masters = [
      for i, vm in libvirt_domain.master : {
        ansible_host = vm.network_interface[0].addresses[0]
        hostname     = "master-${i}"
      }
    ]
    workers = [
      for i, vm in libvirt_domain.worker : {
        ansible_host = vm.network_interface[0].addresses[0]
        hostname     = "worker-${i}"
      }
    ]
  }
}