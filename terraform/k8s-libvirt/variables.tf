variable "cluster_name" {
  description = "Management cluster name"
  type        = string
  default     = "management-cluster"
}

variable "talos_gen_version" {
  description = "trigger-hash key so Terraform knows when to rerun the generator"
  type        = string
  default     = "v1.10.5"
}

variable "k8s_version"     { 
  description = "Kubernetes cluster version"
  type        = string
  default = "1.32.0"   
}


variable "storage_pool" {
  description = "Libvirt storage pool name"
  type        = string
  default     = "k8s_pool"
}

variable "storage_pool_path" {
  type        = string
  default     = "/var/lib/libvirt/images"
}

variable "master_count" {
  description = "Number of master nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "master_vcpus" {
  description = "vCPUs for master nodes"
  type        = number
  default     = 2
}

variable "master_memory" {
  description = "Memory in MB for master nodes"
  type        = number
  default     = 8192
}

variable "master_disk_size" {
  description = "Size of master disks in bytes"
  type        = number
  default     = 21474836480  # 20GB
}

variable "master_extra_disks" {
  description = "Extra disks per master node"
  type        = number
  default     = 1
}

variable "master_extra_disk_size" {
  description = "Size of master extra disks in bytes"
  type        = number
  default     = 10737418240  # 10GB
}

variable "worker_vcpus" {
  description = "vCPUs for worker nodes"
  type        = number
  default     = 4
}

variable "worker_memory" {
  description = "Memory in MB for worker nodes"
  type        = number
  default     = 8192
}

variable "worker_disk_size" {
  description = "Size of worker disks in bytes"
  type        = number
  default     = 21474836480  # 20GB
}


variable "worker_extra_disks" {
  description = "Extra disks per worker node for Nova instances"
  type        = number
  default     = 1
}

variable "worker_extra_disk_size" {
  description = "Size of worker extra disks in bytes"
  type        = number
  default     = 10737418240  # 10GB
}


variable "image_source" {
  description = "URL or path to base OS image"
  type        = string
  default     = "https://github.com/siderolabs/talos/releases/download/v1.10.5/metal-amd64.iso"
}

variable "network_name" {
  description = "Libvirt network name"
  type        = string
  default     = "k8s-net"
}

variable "network_mode" {
  description = "Network mode (nat, bridge)"
  type        = string
  default     = "nat"
  validation {
    condition     = contains(["nat", "bridge"], var.network_mode)
    error_message = "Network mode must be 'nat' or 'bridge'."
  }
}

variable "network_bridge" {
  description = "Bridge interface for bridge network mode"
  type        = string
  default     = "br0"
}

variable "network_cidr" {
  description = "Network CIDR for k8s nodes"
  type        = string
  default     = "10.10.45.0/24"
  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Network CIDR must be a valid CIDR notation."
  }
}