#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root or with sudo.${NC}"
  exit 1
fi

echo -e "${YELLOW}Updating package lists...${NC}"
apt update

echo -e "${YELLOW}Checking and installing required packages if needed...${NC}"
packages=("libvirt-daemon-system" "qemu-system-x86" "genisoimage" "libvirt-clients" "bridge-utils")
to_install=()
for pkg in "${packages[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    to_install+=("$pkg")
  fi
done
if [ ${#to_install[@]} -gt 0 ]; then
  echo -e "${GREEN}Installing missing packages: ${to_install[*]}${NC}"
  apt install -y "${to_install[@]}"
else
  echo -e "${GREEN}All required packages are already installed.${NC}"
fi

echo -e "${YELLOW}Checking libvirtd service status...${NC}"
enabled_status=$(systemctl is-enabled libvirtd 2>&1)
active_status=$(systemctl is-active libvirtd 2>&1)
echo -e "${YELLOW}Enabled status: $enabled_status${NC}"
echo -e "${YELLOW}Active status: $active_status${NC}"

if [ "$enabled_status" != "enabled" ] || [ "$active_status" != "active" ]; then
  echo -e "${GREEN}Enabling and starting libvirtd...${NC}"
  systemctl enable libvirtd
  systemctl start libvirtd
else
  echo -e "${GREEN}libvirtd is already enabled and running.${NC}"
fi

echo -e "${YELLOW}Configuring /etc/libvirt/qemu.conf...${NC}"
QEMU_CONF="/etc/libvirt/qemu.conf"
changes_made=false

if [ ! -f "${QEMU_CONF}.bak" ]; then
  cp "$QEMU_CONF" "${QEMU_CONF}.bak"
  echo -e "${GREEN}Backed up $QEMU_CONF to ${QEMU_CONF}.bak${NC}"
fi

ensure_config() {
  local key="$1"
  local value="$2"
  if grep -q "^$key = " "$QEMU_CONF"; then
    if ! grep -q "^$key = $value" "$QEMU_CONF"; then
      sed -i "s/^$key = .*/$key = $value/" "$QEMU_CONF"
      changes_made=true
    fi
  else
    echo "$key = $value" >> "$QEMU_CONF"
    changes_made=true
  fi
}

ensure_config "user" "\"libvirt-qemu\""
ensure_config "group" "\"libvirt-qemu\""
ensure_config "dynamic_ownership" "1"

# Handle security_driver
if grep -q '^#security_driver =' "$QEMU_CONF"; then
  sed -i 's/^#security_driver =.*/security_driver = "none"/' "$QEMU_CONF"
  changes_made=true
elif ! grep -q '^security_driver = "none"' "$QEMU_CONF"; then
  echo 'security_driver = "none"' >> "$QEMU_CONF"
  changes_made=true
fi

if $changes_made; then
  echo -e "${GREEN}qemu.conf updated with necessary changes.${NC}"
  echo -e "${GREEN}Restarting libvirtd...${NC}"
  systemctl restart libvirtd
else
  echo -e "${GREEN}qemu.conf security_driver is already set to none${NC}"
fi

echo -e "${YELLOW}Verifying libvirt-qemu user and group...${NC}"
if id libvirt-qemu >/dev/null 2>&1; then
  echo -e "${GREEN}libvirt-qemu user and group exist:${NC}"
  user_info=$(id libvirt-qemu)
  echo -e "${GREEN}$user_info${NC}"
else
  echo -e "${RED}Error: libvirt-qemu user or group does not exist.${NC}"
  exit 1
fi

echo -e "${GREEN}Setup complete. Run 'terraform apply' with your configuration.${NC}"