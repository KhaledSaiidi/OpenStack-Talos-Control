#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root or with sudo.${NC}"
  exit 1
fi

echo -e "${YELLOW}Updating package lists …${NC}"
apt update -y

echo -e "${YELLOW}Checking and installing required packages …${NC}"
packages=(
  libvirt-daemon-system 
  qemu-system-x86 
  genisoimage 
  libvirt-clients 
  bridge-utils 
  zstd 
  qemu-utils 
  curl 
  tar
  ovmf
  dnsmasq
  xsltproc
)
to_install=()
for pkg in "${packages[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || to_install+=("$pkg")
done

if [ ${#to_install[@]} -gt 0 ]; then
  echo -e "${GREEN}Installing missing packages: ${to_install[*]}${NC}"
  apt install -y "${to_install[@]}"
else
  echo -e "${GREEN}All required packages are already present.${NC}"
fi

echo -e "${YELLOW}Installing / updating talosctl …${NC}"
curl -sL https://talos.dev/install | sh -s -- --no-sudo >/dev/null

TALOS_BIN="/usr/local/bin/talosctl"
if [ ! -x "$TALOS_BIN" ]; then
  echo -e "${RED}talosctl install failed!${NC}"
  exit 1
fi
echo -e "${GREEN}talosctl $($TALOS_BIN version --short) ready.${NC}"

echo -e "${YELLOW}Checking libvirtd service status …${NC}"
enabled_status=$(systemctl is-enabled libvirtd 2>/dev/null || echo disabled)
active_status=$(systemctl is-active libvirtd 2>/dev/null || echo inactive)
echo -e "${YELLOW}Enabled: ${enabled_status}  Active: ${active_status}${NC}"

if [ "$enabled_status" != "enabled" ] || [ "$active_status" != "active" ]; then
  echo -e "${GREEN}Enabling and starting libvirtd …${NC}"
  systemctl enable libvirtd
  systemctl start libvirtd
fi

echo -e "${YELLOW}Configuring /etc/libvirt/qemu.conf …${NC}"
QEMU_CONF="/etc/libvirt/qemu.conf"
changes_made=false

[ ! -f "${QEMU_CONF}.bak" ] && cp "$QEMU_CONF" "${QEMU_CONF}.bak"

ensure_cfg() {
  local key="$1" value="$2"
  if grep -q "^$key =" "$QEMU_CONF"; then
    grep -q "^$key = $value" "$QEMU_CONF" || { sed -i "s/^$key = .*/$key = $value/" "$QEMU_CONF"; changes_made=true; }
  else
    echo "$key = $value" >> "$QEMU_CONF"; changes_made=true
  fi
}

ensure_cfg "user" "\"libvirt-qemu\""
ensure_cfg "group" "\"libvirt-qemu\""
ensure_cfg "dynamic_ownership" "1"

# security_driver (none)
if grep -q '^#security_driver =' "$QEMU_CONF"; then
  sed -i 's/^#security_driver =.*/security_driver = "none"/' "$QEMU_CONF"; changes_made=true
elif ! grep -q '^security_driver = "none"' "$QEMU_CONF"; then
  echo 'security_driver = "none"' >> "$QEMU_CONF"; changes_made=true
fi

if $changes_made; then
  echo -e "${GREEN}qemu.conf updated; restarting libvirtd …${NC}"
  systemctl restart libvirtd
else
  echo -e "${GREEN}qemu.conf already in desired state.${NC}"
fi

echo -e "${YELLOW}Verifying libvirt-qemu user/group …${NC}"
id libvirt-qemu >/dev/null 2>&1 || { echo -e "${RED}libvirt-qemu user/group missing!${NC}"; exit 1; }

# Check for OVMF firmware
echo -e "${YELLOW}Checking for OVMF UEFI firmware …${NC}"
OVMF_PATH=$(find /usr/share -name "OVMF_CODE.fd" 2>/dev/null | head -n1)
if [ -z "$OVMF_PATH" ]; then
  echo -e "${RED}OVMF firmware not found! Please verify installation.${NC}"
  echo -e "${YELLOW}Try running: sudo apt install ovmf${NC}"
  exit 1
else
  echo -e "${GREEN}OVMF UEFI firmware found at: $OVMF_PATH${NC}"
fi

# Check for dnsmasq service
echo -e "${YELLOW}Checking dnsmasq service status …${NC}"
if systemctl is-enabled dnsmasq >/dev/null 2>&1; then
  echo -e "${GREEN}dnsmasq service is enabled.${NC}"
else
  echo -e "${YELLOW}Enabling and starting dnsmasq service …${NC}"
  systemctl enable dnsmasq
  systemctl start dnsmasq
fi

echo -e "${GREEN}Host preparation complete. Run 'terraform apply'.${NC}"
