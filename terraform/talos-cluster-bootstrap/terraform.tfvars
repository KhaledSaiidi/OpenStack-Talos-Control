# Talos Image version
talos_gen_version = "v1.10.5"

# K8S version
k8s_version = "1.32.0"

# Optional static IP offsets
master_ip_offset = 10
worker_ip_offset = 50

storage_pool_path = "/var/lib/libvirt/images"

enable_ansible = true

# Node counts (HA control plane + room for management add-ons)
master_count = 3
worker_count = 3

# master node resources (Talos control plane, etcd, CAPI controllers)
master_vcpus           = 4
master_memory          = 16384        # 16 GiB
master_root_disk_size  = 107374182400 # 100 GiB
master_extra_disks     = 1
master_extra_disk_size = 214748364800 # 200 GiB data disk

# worker node resources (Argo CD, monitoring stacks, build workloads)
worker_vcpus           = 8
worker_memory          = 32768        # 32 GiB
worker_root_disk_size  = 161061273600 # 150 GiB
worker_extra_disks     = 1
worker_extra_disk_size = 214748364800 # 200 GiB data disk

# Network configuration
network_mode = "nat"
network_cidr = "10.10.45.0/24"
network_name = "k8s-net"

# Storage pool
storage_pool = "k8s_pool"
