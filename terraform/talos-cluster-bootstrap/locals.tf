locals {
  pxe_dir        = "/var/lib/libvirt/pxe/talos"
  ovmf_path      = data.external.ovmf_bridge.result["ovmf_path"]
  ovmf_vars_path = data.external.ovmf_bridge.result["ovmf_vars_path"]

  node_ips = concat(
    [for m in local.generate_ip_mac.masters : m.ip],
    [for w in local.generate_ip_mac.workers : w.ip],
  )

  generate_ip_mac = {
    masters = [
      for idx in range(var.master_count) : {
        name = "master-${idx + 1}"
        ip   = cidrhost(var.network_cidr, var.master_ip_offset + idx)
        mac  = format("52:54:00:aa:bb:%02x", idx)
      }
    ]
    workers = [
      for idx in range(var.worker_count) : {
        name = "worker-${idx + 1}"
        ip   = cidrhost(var.network_cidr, var.worker_ip_offset + idx)
        mac  = format("52:54:00:cc:dd:%02x", idx)
      }
    ]
  }
  ansible_inventory = yamlencode({
    all = {
      children = {
        masters = {
          hosts = {
            for m in local.generate_ip_mac.masters :
            m.name => { ansible_host = m.ip }
          }
        }
        workers = {
          hosts = {
            for w in local.generate_ip_mac.workers :
            w.name => { ansible_host = w.ip }
          }
        }
      }
      vars = {
        talos_version     = var.talos_gen_version
        k8s_version       = var.k8s_version
        cluster_name      = var.cluster_name
        control_plane_vip = var.control_plane_vip
      }
    }
  })

  talos_role_files = fileset("${path.module}/../../ansible/roles/k8s-talos", "**")
  talos_role_hash = sha1(join("", [
    for file in local.talos_role_files :
    filesha1("${path.module}/../../ansible/roles/k8s-talos/${file}")
  ]))
  talos_inventory_hash = sha1(local.ansible_inventory)
}
