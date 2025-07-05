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
    }
  })
}