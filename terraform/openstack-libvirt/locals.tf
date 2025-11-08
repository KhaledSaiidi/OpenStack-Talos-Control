# Cloud_init
locals {
  cloud_init_path = "${path.module}/cloud_init.cfg"
}

# Inventory
locals {
  private_key_path = local_file.private_key.filename
  ansible_inventory = yamlencode({
    all = {
      children = {
        controllers = {
          hosts = {
            for controller in libvirt_domain.controller :
            controller.name => {
              ansible_host                 = controller.network_interface[0].addresses[0]
              ansible_user                 = "ubuntu"
              ansible_ssh_private_key_file = local.private_key_path
            }
          }
        }
        computes = {
          hosts = {
            for compute in libvirt_domain.compute :
            compute.name => {
              ansible_host                 = compute.network_interface[0].addresses[0]
              ansible_user                 = "ubuntu"
              ansible_ssh_private_key_file = local.private_key_path
            }
          }
        }
        storage = {
          hosts = {
            for storage in libvirt_domain.storage :
            storage.name => {
              ansible_host                 = storage.network_interface[0].addresses[0]
              ansible_user                 = "ubuntu"
              ansible_ssh_private_key_file = local.private_key_path
            }
          }
        }
      }
      vars = {
        openstack_secret        = random_password.openstack_secret.result
        private_key_path        = local.private_key_path
        ansible_ssh_common_args = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      }
    }
  })
}