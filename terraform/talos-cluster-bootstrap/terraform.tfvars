# Talos Image version
talos_gen_version           = "v1.10.5"

# K8S version
k8s_version                 = "1.32.0"

# Optional static IP offsets
master_ip_offset = 10
worker_ip_offset = 50

storage_pool_path = "/var/lib/libvirt/images"

enable_ansible = true

# Node counts
master_count = 1
worker_count    = 2

# master node resources
master_vcpus            = 2
master_memory           = 10240         # 10 GiB
master_extra_disks      = 1
master_extra_disk_size  = 68719476736   # 64 GiB

# worker node resources
worker_vcpus            = 2
worker_memory           = 8192          # 8 GiB each
worker_extra_disks      = 1
worker_extra_disk_size  = 68719476736   # 64 GiB

# Network configuration
network_mode           = "nat"
network_cidr           = "10.10.45.0/24"
network_name           = "k8s-net"

# Storage pool
storage_pool           = "k8s_pool"