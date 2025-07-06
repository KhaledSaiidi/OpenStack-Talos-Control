locals {
  image_url     = "https://github.com/siderolabs/talos/releases/download/${var.talos_gen_version}/metal-amd64.raw.zst"
  raw_dir       = "${path.module}/talos-image"
  raw_file      = "${local.raw_dir}/metal-amd64.raw"
  qcow_file     = "${local.raw_dir}/talos-base.qcow2"
}

locals {
  ansible_inventory = yamlencode({
    all = {
      children = {
        masters = {
          hosts = {
            for m in libvirt_domain.master :
            m.name => { ansible_host = m.network_interface[0].addresses[0] }
          }
        }
        workers = {
          hosts = {
            for w in libvirt_domain.worker :
            w.name => { ansible_host = w.network_interface[0].addresses[0] }
          }
        }
      }
      vars = {
        talos_version = var.talos_gen_version
        k8s_version   = var.k8s_version
      }
    }
  })
}