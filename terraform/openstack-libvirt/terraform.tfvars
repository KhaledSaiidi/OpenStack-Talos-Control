# Node counts (minimal for testing locally)
controller_count = 1
compute_count    = 2
storage_count    = 1

# Controller node resources (per OSA guidance: >=16 vCPU, >=32 GiB RAM, >=250 GiB root)
controller_vcpus           = 16
controller_memory          = 49152        # 48 GiB in MiB (gives headroom above 32 GiB minimum)
controller_root_disk_size  = 268435456000 # 250 GiB in bytes
controller_extra_disks     = 1
controller_extra_disk_size = 161061273600 # 150 GiB in bytes (logs + MariaDB backing)

# Compute node resources (Nova hypervisors need room for libvirt + guests)
compute_vcpus           = 16
compute_memory          = 32768        # 32 GiB in MiB
compute_root_disk_size  = 214748364800 # 200 GiB in bytes
compute_extra_disks     = 1
compute_extra_disk_size = 214748364800 # 200 GiB in bytes (ephemeral / placement tests)

# Storage node resources (Cinder backend expects larger I/O footprint)
storage_vcpus           = 8
storage_memory          = 32768        # 32 GiB in MiB
storage_root_disk_size  = 214748364800 # 200 GiB in bytes
storage_extra_disks     = 1
storage_extra_disk_size = 1099511627776 # 1 TiB in bytes for cinder-volumes

# Network configuration
network_mode = "nat"
network_cidr = "10.10.40.0/24"
network_name = "openstack-net"

# Storage pool
storage_pool = "openstack_pool"

# Image source
image_source = "https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img"
