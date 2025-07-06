# Node counts (minimal for testing locally)
controller_count = 1
compute_count    = 1
storage_count    = 1

# Controller node resources
controller_vcpus       = 4
controller_memory      = 2048 #1536
controller_extra_disks = 1
controller_extra_disk_size = 21474836480

# Compute node resources
compute_vcpus          = 2
compute_memory         = 1024
compute_extra_disks    = 1
compute_extra_disk_size = 21474836480

# Storage node resources
storage_vcpus          = 2
storage_memory         = 1024
storage_extra_disks    = 1
storage_extra_disk_size = 21474836480
# Network configuration
network_mode           = "nat"
network_cidr           = "10.10.40.0/24"
network_name           = "openstack-net"

# Storage pool
storage_pool           = "openstack_pool"

# Image source
image_source           = "https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img"