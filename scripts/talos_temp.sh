#!/usr/bin/env bash
set -euo pipefail

### --- Config you can override via env ---
TALOS_VERSION="${TALOS_VERSION:-v1.10.5}"
CLUSTER="${CLUSTER:-mgmt-talos}"
CP="${CP:-10.10.45.10}"
WORKERS="${WORKERS:-10.10.45.50 10.10.45.51}"
TALOS_DIR="${TALOS_DIR:-$HOME/talos}"
ENDPOINT="https://${CP}:6443"

# Wait policy
WAIT_RETRIES="${WAIT_RETRIES:-100}"              # tries
WAIT_INTERVAL="${WAIT_INTERVAL:-15}"             # seconds between tries

### --- Preflight ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: need '$1' in PATH"; exit 1; }; }
need talosctl
command -v nc >/dev/null 2>&1 || echo "INFO: 'nc' not found; will use /dev/tcp fallback."

mkdir -p "$TALOS_DIR"
cd "$TALOS_DIR"

### --- Patch file (install + DHCP on enp1s0) ---
cat > patch-install.yaml <<EOF
machine:
  install:
    disk: /dev/vda
    wipe: true
    image: ghcr.io/siderolabs/installer:${TALOS_VERSION}
  network:
    interfaces:
      - interface: enp1s0
        dhcp: true
EOF

echo ">> Generating cluster config for ${CLUSTER} (${ENDPOINT})..."
talosctl gen config "$CLUSTER" "$ENDPOINT" \
  --output-dir . \
  --config-patch @patch-install.yaml \
  --force

export TALOSCONFIG="$TALOS_DIR/talosconfig"

### --- Apply configs (maintenance API, insecure) ---
echo ">> Applying control-plane config to $CP ..."
talosctl apply-config --insecure -n "$CP" -f controlplane.yaml

echo ">> Applying worker config(s): $WORKERS ..."
for n in $WORKERS; do
  talosctl apply-config --insecure -n "$n" -f worker.yaml
done

### --- Wait helpers ---
wait_port() {
  local host="$1" port="$2"
  local i=1
  while (( i <= WAIT_RETRIES )); do
    if command -v nc >/dev/null 2>&1; then
      if nc -z -w2 "$host" "$port" >/dev/null 2>&1; then return 0; fi
    else
      # bash /dev/tcp fallback (wrapped so 'timeout' doesn’t kill the shell)
      if timeout 2 bash -lc ">/dev/tcp/$host/$port" >/dev/null 2>&1; then return 0; fi
    fi
    echo "  [$i/$WAIT_RETRIES] $host:$port not up yet; retrying in ${WAIT_INTERVAL}s..."
    i=$((i+1))
    sleep "$WAIT_INTERVAL"
  done
  return 1
}

### --- Wait for CP maintenance API back up after install ---
echo ">> Waiting for Talos maintenance API on $CP:50000 ..."
wait_port "$CP" 50000 || { echo "ERROR: timeout waiting for $CP:50000"; exit 1; }
echo "OK: $CP:50000 is up."

# Optional: see it answer
talosctl -n "$CP" -e "$CP" version || true

### --- Bootstrap etcd on CP ---
echo ">> Bootstrapping etcd on control-plane ($CP) ..."
talosctl -n "$CP" -e "$CP" bootstrap

### --- Wait for kube-apiserver, then pull kubeconfig ---
echo ">> Waiting for Kubernetes API on $CP:6443 ..."
wait_port "$CP" 6443 || { echo "ERROR: timeout waiting for kube-apiserver on $CP:6443"; exit 1; }

echo ">> Fetching kubeconfig ..."
talosctl -n "$CP" -e "$CP" kubeconfig --force >/dev/null
echo "kubeconfig written to: $PWD/kubeconfig"

### --- Sanity checks ---
echo ">> Talos health (control-plane):"
talosctl -n "$CP" -e "$CP" health --wait-timeout 10m || true

echo ">> Talos versions (workers):"
for n in $WORKERS; do
  talosctl -n "$n" -e "$CP" version || true
done

echo ">> Done. Export this to use kubectl:"
echo "   export KUBECONFIG=\"$PWD/kubeconfig\""

