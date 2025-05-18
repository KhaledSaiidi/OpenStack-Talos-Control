# Cloud_init
locals {
  cloud_init_path = fileexists("${path.module}/cloud_init.cfg") ? "${path.module}/cloud_init.cfg" : "${path.module}/cloud_init.cfg.example"
}

# Inventory
locals {
  ansible_inventory = yamlencode({
    all = {
      children = {
        controllers = {
          hosts = {
            for controller in libvirt_domain.controller :
            controller.name => {
              ansible_host = controller.network_interface[0].addresses[0]
              ansible_user = "ubuntu"
              ansible_ssh_private_key_file = "${path.module}/openstack_private_key.pem"
            }
          }
        }
        computes = {
          hosts = {
            for compute in libvirt_domain.compute :
            compute.name => {
              ansible_host = compute.network_interface[0].addresses[0]
              ansible_user = "ubuntu"
              ansible_ssh_private_key_file = "${path.module}/openstack_private_key.pem"
            }
          }
        }
        storage = {
          hosts = {
            for storage in libvirt_domain.storage :
            storage.name => {
              ansible_host = storage.network_interface[0].addresses[0]
              ansible_user = "ubuntu"
              ansible_ssh_private_key_file = "${path.module}/openstack_private_key.pem"
            }
          }
        }
      }
      vars = {
        openstack_secret = random_password.openstack_secret.result
      }
    }
  })
}