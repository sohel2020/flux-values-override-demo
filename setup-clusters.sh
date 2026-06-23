#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
CLUSTER_1="tenant-1"
CLUSTER_2="tenant-2"
FLUX_OPERATOR_VERSION="2.4.0"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
err()  { echo -e "${RED}[!]${NC} $1" >&2; }

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

# --- Create kind clusters ---
create_cluster() {
  local name=$1
  if kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    info "Cluster ${name} already exists, skipping creation."
  else
    log "Creating kind cluster: ${name}"
    kind create cluster --name "$name" --wait 60s
  fi
}

create_cluster "$CLUSTER_1"
create_cluster "$CLUSTER_2"

# --- Install Flux Operator via Helm on a cluster ---
install_flux_operator() {
  local ctx=$1
  log "Installing Flux Operator on ${ctx}"
  kubectl config use-context "kind-${ctx}"

  helm upgrade --install flux-operator \
    oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
    --namespace flux-system \
    --create-namespace \
    --wait
}

install_flux_operator "$CLUSTER_1"
install_flux_operator "$CLUSTER_2"

# --- Deploy FluxInstance (all controllers) on a cluster ---
deploy_flux_instance() {
  local ctx=$1
  log "Deploying FluxInstance (all controllers) on ${ctx}"
  kubectl config use-context "kind-${ctx}"

  kubectl apply -f - <<'EOF'
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
  cluster:
    type: kubernetes
  kustomize:
    patches: []
EOF

  log "Waiting for Flux controllers to become ready on ${ctx}..."
  kubectl -n flux-system wait --for=condition=Ready fluxinstance/flux --timeout=120s
}

deploy_flux_instance "$CLUSTER_1"
deploy_flux_instance "$CLUSTER_2"

# --- Summary ---
echo ""
log "Setup complete!"
echo ""

for cluster in "$CLUSTER_1" "$CLUSTER_2"; do
  info "--- ${cluster} ---"
  kubectl config use-context "kind-${cluster}" >/dev/null
  kubectl -n flux-system get pods
  echo ""
done

info "Switch contexts with:"
info "  kubectl config use-context kind-${CLUSTER_1}"
info "  kubectl config use-context kind-${CLUSTER_2}"
