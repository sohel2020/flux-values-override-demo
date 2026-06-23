#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
CLUSTERS=(tenant-1 tenant-2 tenant-3)

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

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force]

Delete all kind clusters created by setup-clusters.sh:
  ${CLUSTERS[*]}

Options:
  --force, -y   Skip confirmation prompt
EOF
}

# --- Args ---
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force|-y) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

# --- Preflight ---
for cmd in docker kind; do
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd not found. Install it first."
    exit 1
  fi
done

if ! docker info &>/dev/null; then
  err "Docker daemon not running."
  exit 1
fi

# --- Confirm ---
if [[ "$FORCE" != true ]]; then
  info "This will delete the following kind clusters:"
  for cluster in "${CLUSTERS[@]}"; do
    info "  - ${cluster}"
  done
  read -r -p "Continue? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    info "Aborted."
    exit 0
  fi
fi

# --- Delete kind clusters in parallel ---
delete_cluster() {
  local name=$1
  if kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    cluster_log "$name" "Deleting kind cluster"
    kind delete cluster --name "$name"
    cluster_log "$name" "Deleted"
  else
    cluster_info "$name" "Cluster does not exist, skipping."
  fi
}

pids=()
for cluster in "${CLUSTERS[@]}"; do
  delete_cluster "$cluster" &
  pids+=($!)
done

failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done

if (( failed )); then
  err "One or more clusters failed to delete."
  exit 1
fi

echo ""
log "Teardown complete!"
