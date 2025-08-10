#!/usr/bin/env bash
set -euo pipefail

net_name="${1:-}"

bridge_if="$(virsh net-info "$net_name" 2>/dev/null | awk '/Bridge/ {print $2}')"

ovmf_code=""
for f in \
  /usr/share/OVMF/OVMF_CODE_4M.fd \
  /usr/share/OVMF/OVMF_CODE.fd
do
  if [[ -r "$f" ]]; then ovmf_code="$f"; break; fi
done

if [[ -z "$ovmf_code" ]]; then
  ovmf_code="$(ls /usr/share/OVMF/OVMF_CODE*.fd 2>/dev/null | grep -Ev '(secboot|\.ms\.|snakeoil)' | head -n1 || true)"
fi

if [[ -z "$ovmf_code" ]]; then
  echo "Failed to locate non-secure OVMF CODE file" >&2
  exit 1
fi

if [[ "$ovmf_code" == *"_4M.fd" && -r /usr/share/OVMF/OVMF_VARS_4M.fd ]]; then
  ovmf_vars="/usr/share/OVMF/OVMF_VARS_4M.fd"
else
  ovmf_vars="/usr/share/OVMF/OVMF_VARS.fd"
fi

printf '{ "bridge_interface": "%s", "ovmf_path": "%s", "ovmf_vars_path": "%s" }\n' \
  "${bridge_if:-}" "$ovmf_code" "$ovmf_vars"
