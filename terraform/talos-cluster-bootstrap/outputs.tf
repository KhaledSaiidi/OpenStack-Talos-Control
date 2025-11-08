output "master_nodes" {
  description = "Details of master nodes"
  value = [
    for i, vm in libvirt_domain.master : {
      hostname = local.generate_ip_mac.masters[i].name
      mac      = local.generate_ip_mac.masters[i].mac
      ip       = local.generate_ip_mac.masters[i].ip
      disks = concat(
        [libvirt_volume.master_disk[i].id],
        [
          for j in range(var.master_extra_disks) :
          libvirt_volume.master_extra_disk[
            i * var.master_extra_disks + j
          ].id
        ]
      )
    }
  ]
}

output "worker_nodes" {
  description = "Details of worker nodes"
  value = [
    for i, vm in libvirt_domain.worker : {
      hostname = local.generate_ip_mac.workers[i].name
      mac      = local.generate_ip_mac.workers[i].mac
      ip       = local.generate_ip_mac.workers[i].ip
      disks = concat(
        [libvirt_volume.worker_disk[i].id],
        [
          for j in range(var.worker_extra_disks) :
          libvirt_volume.worker_extra_disk[
            i * var.worker_extra_disks + j
          ].id
        ]
      )
    }
  ]
}

output "network_name" {
  description = "Name of the created libvirt network"
  value       = libvirt_network.k8s_net.name
}
