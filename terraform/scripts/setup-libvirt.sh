#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

echo "Installing libvirt, QEMU, genisoimage, libvirt-clients, and bridge-utils..."
apt update
apt install -y libvirt-daemon-system qemu-kvm genisoimage libvirt-clients bridge-utils

echo "Starting and enabling libvirtd..."
systemctl enable libvirtd
systemctl start libvirtd

echo "Configuring /etc/libvirt/qemu.conf..."
QEMU_CONF="/etc/libvirt/qemu.conf"

if [ ! -f "${QEMU_CONF}.bak" ]; then
  cp "$QEMU_CONF" "${QEMU_CONF}.bak"
  echo "Backed up $QEMU_CONF to ${QEMU_CONF}.bak"
fi

# Configure user, group, and dynamic ownership
sed -i '/^#user =/c\user = "libvirt-qemu"' "$QEMU_CONF"
sed -i '/^#group =/c\group = "libvirt-qemu"' "$QEMU_CONF"
sed -i '/^#dynamic_ownership =/c\dynamic_ownership = 1' "$QEMU_CONF"

grep -q '^user = "libvirt-qemu"' "$QEMU_CONF" || echo 'user = "libvirt-qemu"' >> "$QEMU_CONF"
grep -q '^group = "libvirt-qemu"' "$QEMU_CONF" || echo 'group = "libvirt-qemu"' >> "$QEMU_CONF"
grep -q '^dynamic_ownership = 1' "$QEMU_CONF" || echo 'dynamic_ownership = 1' >> "$QEMU_CONF"

# Ensure security_driver is set to "none" (uncomment if exists or add if not)
if grep -q '^#security_driver =' "$QEMU_CONF"; then
  sed -i 's/^#security_driver =.*/security_driver = "none"/' "$QEMU_CONF"
elif ! grep -q '^security_driver = "none"' "$QEMU_CONF"; then
  echo 'security_driver = "none"' >> "$QEMU_CONF"
fi

echo "qemu.conf updated with:"
echo "  - user = libvirt-qemu"
echo "  - group = libvirt-qemu"
echo "  - dynamic_ownership = 1"
echo "  - security_driver = none"

echo "Restarting libvirtd..."
systemctl restart libvirtd

echo "Verifying libvirt-qemu user and group..."
if id libvirt-qemu >/dev/null 2>&1; then
  echo "libvirt-qemu user and group exist:"
  id libvirt-qemu
else
  echo "Error: libvirt-qemu user or group does not exist."
  exit 1
fi

echo "Setup complete. Run 'terraform apply' with your configuration."