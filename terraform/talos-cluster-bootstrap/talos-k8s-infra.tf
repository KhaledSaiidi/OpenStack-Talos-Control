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

resource "libvirt_pool" "k8s_pool" {
  name = var.storage_pool
  type = "dir"
  target {
    path = var.storage_pool_path
  }
}

resource "null_resource" "talos_pxe_files" {
  triggers = {
    talos_version  = var.talos_gen_version
    pxe_dir        = local.pxe_dir
    tftp_server_ip = cidrhost(var.network_cidr, 1) # libvirt NAT gateway IP
  }

  provisioner "local-exec" {
    command = <<-EOF
      /bin/bash -euxo pipefail

      # Ensure NVRAM dir exists (libvirt creates files, not the directory)
      sudo install -d -m 0755 -o root -g root /var/lib/libvirt/qemu/nvram

      # Ensure TFTP root exists
      sudo mkdir -p '${local.pxe_dir}'

      # Talos kernel & initramfs (versioned)
      sudo curl -fsSL -o '${local.pxe_dir}/vmlinuz-amd64' \
        'https://github.com/siderolabs/talos/releases/download/${var.talos_gen_version}/vmlinuz-amd64'
      sudo curl -fsSL -o '${local.pxe_dir}/initramfs-amd64.xz' \
        'https://github.com/siderolabs/talos/releases/download/${var.talos_gen_version}/initramfs-amd64.xz'

      # iPXE EFI binary (prefer distro path if available)
      if [ -r /usr/lib/ipxe/ipxe.efi ]; then
        sudo cp /usr/lib/ipxe/ipxe.efi '${local.pxe_dir}/ipxe.efi'
      elif [ -r /usr/share/ipxe/ipxe.efi ]; then
        sudo cp /usr/share/ipxe/ipxe.efi '${local.pxe_dir}/ipxe.efi'
      else
        sudo curl -fsSL -o '${local.pxe_dir}/ipxe.efi' 'https://boot.ipxe.org/ipxe.efi'
      fi

      # iPXE script: chain-load Talos from this TFTP root (no HTTP, no configurl)
      sudo tee '${local.pxe_dir}/talos.ipxe' >/dev/null <<'IPXE'
#!ipxe
dhcp
set base tftp://${cidrhost(var.network_cidr, 1)}
kernel $${base}/vmlinuz-amd64 talos.platform=metal slab_nomerge pti=on ip=dhcp console=ttyS0,115200 console=tty0
initrd $${base}/initramfs-amd64.xz
boot
IPXE

      # World-readable so dnsmasq/tftp can serve them
      sudo chmod -R a+rX '${local.pxe_dir}'
    EOF
  }
}

# Libvirt network
resource "libvirt_network" "k8s_net" {
  depends_on = [null_resource.talos_pxe_files]
  name       = var.network_name
  mode       = var.network_mode # "nat" or "bridge"
  bridge     = var.network_mode == "bridge" ? var.network_bridge : null
  addresses  = var.network_mode == "nat" ? [var.network_cidr] : []
  autostart  = true

  dhcp { enabled = var.network_mode == "nat" }
  dns { enabled = var.network_mode == "nat" }

  # Per-network dnsmasq config (block-style)
  dnsmasq_options {
    # TFTP
    options {
      option_name = "enable-tftp"
    }
    options {
      option_name  = "tftp-root"
      option_value = local.pxe_dir
    }

    # Lease pool
    options {
      option_name  = "dhcp-range"
      option_value = "${cidrhost(var.network_cidr, 100)},${cidrhost(var.network_cidr, 200)},12h"
    }

    # Default gateway & DNS for guests
    options {
      option_name  = "dhcp-option"
      option_value = "option:router,${cidrhost(var.network_cidr, 1)}"
    }
    options {
      option_name  = "dhcp-option"
      option_value = "option:dns-server,${cidrhost(var.network_cidr, 1)}"
    }

    # 🔹 Tell clients explicitly who the TFTP/next-server is (Option 66)
    options {
      option_name  = "dhcp-option"
      option_value = "66,${cidrhost(var.network_cidr, 1)}"
    }

    # Detect UEFI
    options {
      option_name  = "dhcp-match"
      option_value = "set:efi,option:client-arch,7"
    }
    options {
      option_name  = "dhcp-match"
      option_value = "set:efi,option:client-arch,9"
    }
    options {
      option_name  = "dhcp-match"
      option_value = "set:efi,option:client-arch,11"
    }

    # Detect iPXE (second DHCP)
    options {
      option_name  = "dhcp-userclass"
      option_value = "set:ipxe,iPXE"
    }
    options {
      option_name  = "dhcp-match"
      option_value = "set:ipxe,175"
    }

    # Stage 1 for UEFI: give iPXE only if NOT already iPXE
    # 🔹 Include explicit next-server ip as the 3rd field
    options {
      option_name  = "dhcp-boot"
      option_value = "tag:efi,tag:!ipxe,ipxe.efi,,${cidrhost(var.network_cidr, 1)}"
    }

    # Stage 2 for iPXE: chain to our script (MUST be last dhcp-boot)
    # 🔹 Include explicit next-server ip as the 3rd field
    options {
      option_name  = "dhcp-boot"
      option_value = "tag:ipxe,talos.ipxe,,${cidrhost(var.network_cidr, 1)}"
    }

    # Static DHCP bindings (MAC -> IP)
    dynamic "options" {
      for_each = concat(local.generate_ip_mac.masters, local.generate_ip_mac.workers)
      content {
        option_name  = "dhcp-host"
        option_value = "${options.value.mac},${options.value.ip}"
      }
    }

    # Uncomment while debugging
    options { option_name = "log-dhcp" }
  }
}


data "external" "ovmf_bridge" {
  program    = ["../../scripts/detect_ovmf_bridge.sh", var.network_name]
  depends_on = [libvirt_network.k8s_net]
}

resource "libvirt_volume" "master_disk" {
  count  = var.master_count
  name   = "master-${count.index + 1}-disk.qcow2"
  pool   = libvirt_pool.k8s_pool.name
  size   = var.master_root_disk_size
  format = "qcow2"
}

resource "libvirt_volume" "worker_disk" {
  count  = var.worker_count
  name   = "worker-${count.index + 1}-disk.qcow2"
  pool   = libvirt_pool.k8s_pool.name
  size   = var.worker_root_disk_size
  format = "qcow2"
}

resource "libvirt_volume" "master_extra_disk" {
  count  = var.master_count * var.master_extra_disks
  name   = "master-${floor(count.index / var.master_extra_disks) + 1}-extra-disk-${count.index % var.master_extra_disks + 1}"
  pool   = libvirt_pool.k8s_pool.name
  size   = var.master_extra_disk_size
  format = "qcow2"
}

resource "libvirt_volume" "worker_extra_disk" {
  count  = var.worker_count * var.worker_extra_disks
  name   = "worker-${floor(count.index / var.worker_extra_disks) + 1}-extra-disk-${count.index % var.worker_extra_disks + 1}"
  pool   = libvirt_pool.k8s_pool.name
  size   = var.worker_extra_disk_size
  format = "qcow2"
}
# Masters
resource "libvirt_domain" "master" {
  count     = var.master_count
  name      = "master-${count.index + 1}"
  vcpu      = var.master_vcpus
  memory    = var.master_memory
  firmware  = local.ovmf_path
  machine   = "q35"
  autostart = true
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
    mac            = local.generate_ip_mac.masters[count.index].mac
    wait_for_lease = true
  }

  cpu {
    mode = "host-passthrough"
  }
  nvram {
    file     = "/var/lib/libvirt/qemu/nvram/${format("master-%d_%d_VARS.fd", count.index + 1, var.nvram_epoch)}"
    template = local.ovmf_vars_path
  }
  xml {
    xslt = file("${path.module}/templates/uefi-bootorder.xsl")
  }
  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "127.0.0.1"
    autoport       = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

# Workers
resource "libvirt_domain" "worker" {
  count     = var.worker_count
  name      = "worker-${count.index + 1}"
  vcpu      = var.worker_vcpus
  memory    = var.worker_memory
  firmware  = local.ovmf_path
  machine   = "q35"
  autostart = true

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
    mac            = local.generate_ip_mac.workers[count.index].mac
    wait_for_lease = true
  }

  cpu {
    mode = "host-passthrough"
  }
  nvram {
    file     = "/var/lib/libvirt/qemu/nvram/${format("worker-%d_%d_VARS.fd", count.index + 1, var.nvram_epoch)}"
    template = local.ovmf_vars_path
  }
  xml {
    xslt = file("${path.module}/templates/uefi-bootorder.xsl")
  }
  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "127.0.0.1"
    autoport       = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

resource "local_file" "ansible_inventory" {
  content         = local.ansible_inventory
  filename        = "${path.module}/ansible_inventory.yaml"
  file_permission = "0644"
}

resource "null_resource" "wait_for_talos" {
  depends_on = [
    libvirt_domain.master,
    libvirt_domain.worker,
    libvirt_network.k8s_net,
    null_resource.talos_pxe_files,
  ]

  triggers = {
    node_ips      = join(",", local.node_ips)
    retries       = tostring(var.talos_boot_retries)
    interval      = tostring(var.talos_boot_retry_interval_seconds)
    talos_version = var.talos_gen_version
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      node_ips="${self.triggers.node_ips}"
      retries="${self.triggers.retries}"
      interval="${self.triggers.interval}"

      check_port() {
        local ip="$1"
        if command -v nc >/dev/null 2>&1; then
          nc -z -w2 "$ip" 50000
        else
          timeout 2 bash -lc ">/dev/tcp/$ip/50000" >/dev/null 2>&1
        fi
      }

      for ip in $(echo "$node_ips" | tr ',' ' '); do
        printf 'Waiting for %s:50000 (Talos maintenance API) - max %s tries, every %ss\n' "$ip" "$retries" "$interval"
        attempt=0
        until check_port "$ip"; do
          attempt=$((attempt + 1))
          if (( attempt >= retries )); then
            printf 'ERROR: %s:50000 not reachable after %s attempts.\n' "$ip" "$retries" >&2
            exit 1
          fi
          remaining=$((retries - attempt))
          printf 'Not up yet: %s:50000 - retry %s/%s (%s left).\n' "$ip" "$attempt" "$retries" "$remaining"
          sleep "$interval"
        done
        printf 'OK: %s:50000 is reachable.\n' "$ip"
      done
    EOT
  }
}

resource "null_resource" "ansible_provision" {
  count = var.enable_ansible ? 1 : 0
  depends_on = [
    null_resource.wait_for_talos,
    local_file.ansible_inventory,
  ]

  triggers = {
    talos_role_hash = local.talos_role_hash
    tfvars_hash     = filesha1("${path.module}/terraform.tfvars")
    inventory_hash  = local.talos_inventory_hash
  }
  provisioner "local-exec" {
    command = <<EOF
      PYTHONUNBUFFERED=1 ansible-playbook \
        -i ${local_file.ansible_inventory.filename} \
        ../../ansible/roles/k8s-talos/site.yaml \
        || exit 1
    EOF
  }
}

resource "null_resource" "cleanup_pxe" {
  triggers = {
    pxe_dir = local.pxe_dir
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      sudo rm -rf ${self.triggers.pxe_dir}
    EOT
  }
}
