#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

# Update package list and install required packages
echo "Installing libvirt, QEMU, genisoimage, libvirt-clients, and bridge-utils..."
apt update
apt install -y libvirt-daemon-system qemu-kvm genisoimage libvirt-clients bridge-utils

# Start and enable libvirtd service
echo "Starting and enabling libvirtd..."
systemctl enable libvirtd
systemctl start libvirtd

# Set up storage pool
POOL_NAME="openstack_pool"
POOL_DIR="/var/lib/libvirt/images"
echo "Setting up storage pool '$POOL_NAME' at $POOL_DIR..."
mkdir -p "$POOL_DIR"
chown root:root "$POOL_DIR"
chmod 755 "$POOL_DIR"

# Define, build, start, and autostart the pool
virsh pool-define-as "$POOL_NAME" dir --target "$POOL_DIR"
virsh pool-build "$POOL_NAME"
virsh pool-start "$POOL_NAME"
virsh pool-autostart "$POOL_NAME"

# Verify pool is active
if virsh pool-list --all | grep -q "$POOL_NAME.*active"; then
  echo "Storage pool '$POOL_NAME' is active."
else
  echo "Failed to activate storage pool '$POOL_NAME'."
  exit 1
fi

echo "Setup complete. Run 'terraform apply' with your configuration."