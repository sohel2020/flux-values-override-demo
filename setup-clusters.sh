#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
CLUSTERS=(tenant-1 tenant-2 tenant-3)
FLUX_OPERATOR_VERSION="2.4.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
err()  { echo -e "${RED}[!]${NC} $1" >&2; }

cluster_log()  { log "[$1] $2"; }
cluster_info() { info "[$1] $2"; }
cluster_err()  { err "[$1] $2"; }

# --- Preflight ---
for cmd in docker kind kubectl helm; do
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd not found. Install it first."
    exit 1
  fi
done

if ! docker info &>/dev/null; then
  err "Docker daemon not running."
  exit 1
fi

# --- Setup one cluster end-to-end ---
setup_cluster() {
  local name=$1
  local ctx="kind-${name}"
  local tenant_manifest="${SCRIPT_DIR}/tenants-kustomization/${name}.yaml"

  if [[ ! -f "$tenant_manifest" ]]; then
    cluster_err "$name" "Tenant manifest not found: ${tenant_manifest}"
    return 1
  fi

  if kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    cluster_info "$name" "Cluster already exists, skipping creation."
  else
    cluster_log "$name" "Creating kind cluster"
    kind create cluster --name "$name" --wait 60s
  fi

  cluster_log "$name" "Installing Flux Operator"
  helm upgrade --install flux-operator \
    oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
    --namespace flux-system \
    --create-namespace \
    --kube-context "$ctx" \
    --wait

  cluster_log "$name" "Deploying FluxInstance (all controllers)"
  kubectl --context "$ctx" apply -f - <<'EOF'
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution:
    version: "2.x"
    registry: "ghcr.io/fluxcd"
  components:
    - source-controller
    - kustomize-controller
    - helm-controller
    - notification-controller
    - image-reflector-controller
    - image-automation-controller
    - source-watcher
  cluster:
    type: kubernetes
  kustomize:
    patches: []
EOF

  cluster_log "$name" "Waiting for Flux controllers to become ready"
  kubectl --context "$ctx" -n flux-system wait --for=condition=Ready fluxinstance/flux --timeout=120s

  cluster_log "$name" "Applying tenant kustomization (${tenant_manifest})"
  kubectl --context "$ctx" apply -f "$tenant_manifest"

  cluster_log "$name" "Setup complete"
}

# --- Run cluster setup in parallel ---
pids=()
for cluster in "${CLUSTERS[@]}"; do
  setup_cluster "$cluster" &
  pids+=($!)
done

failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done

if (( failed )); then
  err "One or more clusters failed to set up."
  exit 1
fi

# --- Summary ---
echo ""
log "Setup complete!"
echo ""

for cluster in "${CLUSTERS[@]}"; do
  info "--- ${cluster} ---"
  kubectl --context "kind-${cluster}" -n flux-system get pods
  echo ""
done
