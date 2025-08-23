# Node counts (minimal for testing locally)
controller_count = 1
compute_count    = 2
storage_count    = 1

# Controller node resources
controller_vcpus           = 2
controller_memory          = 12288          # 12 GiB in MiB
controller_extra_disks     = 1
controller_extra_disk_size = 68719476736    # 64 GiB in bytes

# Compute node resources
compute_vcpus              = 2
compute_memory             = 8192           # 8 GiB in MiB
compute_extra_disks        = 1
compute_extra_disk_size    = 68719476736    # 64 GiB in bytes

# Storage node resources
storage_vcpus              = 2
storage_memory             = 10240          # 10 GiB in MiB
storage_extra_disks        = 1
storage_extra_disk_size    = 137438953472   # 128 GiB in bytes

# Network configuration
network_mode           = "nat"
network_cidr           = "10.10.40.0/24"
network_name           = "openstack-net"

# Storage pool
storage_pool           = "openstack_pool"

# Image source
image_source           = "https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img"