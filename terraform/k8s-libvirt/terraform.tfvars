# Node counts
master_count = 1
worker_count    = 2

# master node resources
master_vcpus       = 4
master_memory      = 2048 #1536
master_extra_disks = 1
master_disk_size = 21474836480
master_extra_disk_size = 10737418240

# worker node resources
worker_vcpus          = 2
worker_memory         = 1024
worker_extra_disks    = 1
worker_disk_size = 21474836480
worker_extra_disk_size = 10737418240

# Network configuration
network_mode           = "nat"
network_cidr           = "10.10.45.0/24"
network_name           = "k8s-net"

# Storage pool
storage_pool           = "k8s_pool"

# Image source
image_source           = "https://github.com/siderolabs/talos/releases/download/v1.10.5/metal-amd64.iso"