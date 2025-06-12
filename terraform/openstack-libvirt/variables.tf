variable "storage_pool" {
  description = "Libvirt storage pool name"
  type        = string
  default     = "openstack_pool"
}

variable "storage_pool_path" {
  description = "Number of compute nodes"
  type        = string
  default     = "/var/lib/libvirt/images"
}

variable "controller_count" {
  description = "Number of controller nodes"
  type        = number
  default     = 1
  validation {
    condition     = var.controller_count >= 1
    error_message = "Controller count must be at least 1."
  }
}

variable "compute_count" {
  description = "Number of compute nodes"
  type        = number
  default     = 1
}

variable "storage_count" {
  description = "Number of storage nodes"
  type        = number
  default     = 1
}

variable "controller_vcpus" {
  description = "vCPUs for controller nodes"
  type        = number
  default     = 4
  validation {
    condition     = var.controller_vcpus >= 2
    error_message = "Controller vCPUs must be at least 2."
  }
}

variable "controller_memory" {
  description = "Memory in MB for controller nodes"
  type        = number
  default     = 8192
  validation {
    condition     = var.controller_memory >= 1024
    error_message = "Controller memory must be at least 1024 MB for testing"
  }
}

variable "controller_disk_size" {
  description = "Size of controller disks in bytes"
  type        = number
  default     = 21474836480  # 20GB
  validation {
    condition     = var.controller_disk_size >= 21474836480
    error_message = "Controller disk size must be at least 20GB."
  }
}

variable "controller_extra_disks" {
  description = "Extra disks per controller node for OpenStack services"
  type        = number
  default     = 1
  validation {
    condition     = var.controller_extra_disks >= 0
    error_message = "Controller extra disks must be non-negative."
  }
}

variable "controller_extra_disk_size" {
  description = "Size of controller extra disks in bytes"
  type        = number
  default     = 10737418240  # 10GB
  validation {
    condition     = var.controller_extra_disk_size >= 10737418240
    error_message = "Controller disk size must be at least 10GB."
  }
}

variable "compute_vcpus" {
  description = "vCPUs for compute nodes"
  type        = number
  default     = 4
  validation {
    condition     = var.compute_vcpus >= 2
    error_message = "Compute vCPUs must be at least 2."
  }
}

variable "compute_memory" {
  description = "Memory in MB for compute nodes"
  type        = number
  default     = 8192
  validation {
    condition     = var.compute_memory >= 1024
    error_message = "Compute memory must be at least 1024 MB for testing."
  }
}

variable "compute_disk_size" {
  description = "Size of compute disks in bytes"
  type        = number
  default     = 21474836480  # 20GB
  validation {
    condition     = var.compute_disk_size >= 21474836480
    error_message = "Compute disk size must be at least 20GB."
  }
}


variable "compute_extra_disks" {
  description = "Extra disks per compute node for Nova instances"
  type        = number
  default     = 1
  validation {
    condition     = var.compute_extra_disks >= 0
    error_message = "Compute extra disks must be non-negative."
  }
}

variable "compute_extra_disk_size" {
  description = "Size of compute extra disks in bytes"
  type        = number
  default     = 10737418240  # 10GB
  validation {
    condition     = var.compute_extra_disk_size >= 10737418240
    error_message = "Compute disk size must be at least 10GB."
  }
}

variable "storage_vcpus" {
  description = "vCPUs for storage nodes"
  type        = number
  default     = 2
  validation {
    condition     = var.storage_vcpus >= 2
    error_message = "Storage vCPUs must be at least 2."
  }
}

variable "storage_memory" {
  description = "Memory in MB for storage nodes"
  type        = number
  default     = 4096
  validation {
    condition     = var.storage_memory >= 1024
    error_message = "Storage memory must be at least 1024 MB for testing."
  }
}

variable "storage_disk_size" {
  description = "Size of storage disks in bytes"
  type        = number
  default     = 21474836480  # 20GB
  validation {
    condition     = var.storage_disk_size >= 21474836480
    error_message = "Storage disk size must be at least 20GB."
  }
}

variable "storage_extra_disks" {
  description = "Extra disks per storage node for Cinder/Swift"
  type        = number
  default     = 1
  validation {
    condition     = var.storage_extra_disks >= 1
    error_message = "Storage extra disks must be at least 1."
  }
}

variable "storage_extra_disk_size" {
  description = "Size of storage extra disks in bytes"
  type        = number
  default     = 21474836480  # 20GB
  validation {
    condition     = var.storage_extra_disk_size >= 21474836480
    error_message = "Storage disk size must be at least 20GB."
  }
}

variable "image_source" {
  description = "URL or path to base OS image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

variable "network_name" {
  description = "Libvirt network name"
  type        = string
  default     = "openstack-net"
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
  description = "Network CIDR for OpenStack nodes"
  type        = string
  default     = "10.10.40.0/24"
  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Network CIDR must be a valid CIDR notation."
  }
}