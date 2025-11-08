# Node counts (minimal for testing locally)
controller_count = 1
compute_count    = 2
storage_count    = 1

# Controller node resources (deployment + HA services)
controller_vcpus           = 8
controller_memory          = 24576        # 24 GiB in MiB
controller_root_disk_size  = 161061273600 # 150 GiB in bytes
controller_extra_disks     = 1
controller_extra_disk_size = 85899345920 # 80 GiB in bytes

# Compute node resources (Nova hypervisors)
compute_vcpus           = 8
compute_memory          = 16384        # 16 GiB in MiB
compute_root_disk_size  = 128849018880 # 120 GiB in bytes
compute_extra_disks     = 1
compute_extra_disk_size = 68719476736 # 64 GiB in bytes

# Storage node resources (Cinder backend)
storage_vcpus           = 6
storage_memory          = 16384        # 16 GiB in MiB
storage_root_disk_size  = 107374182400 # 100 GiB in bytes
storage_extra_disks     = 1
storage_extra_disk_size = 137438953472 # 128 GiB in bytes

# Network configuration
network_mode = "nat"
network_cidr = "10.10.40.0/24"
network_name = "openstack-net"

# Storage pool
storage_pool = "openstack_pool"

# Image source
image_source = "https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img"
