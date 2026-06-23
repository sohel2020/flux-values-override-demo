# Flux Values Override Demo

## What This Does

This project demonstrates how Flux CD can deploy the same Helm chart with different configurations per tenant using `valuesFiles` and the `${tenantName}` variable substitution.

A single `HelmRelease` definition serves multiple tenants. Each tenant gets its own values file (`values-tenant-1.yaml`, `values-tenant-2.yaml`, etc.) that overrides the base `values.yaml`. Flux substitutes `${tenantName}` at reconciliation time, so each tenant picks up its own overrides automatically.

## Project Structure

```
.
├── gitops/
│   ├── kustomization.yaml      # Kustomize entry point, includes podinfo.yaml
│   └── podinfo.yaml            # Flux HelmRelease (references chart + valuesFiles)
├── helm-charts/
│   └── podinfo/
│       ├── Chart.yaml           # Wrapper chart depending on upstream podinfo
│       ├── Chart.lock
│       ├── charts/              # Cached upstream podinfo chart (.tgz)
│       ├── templates/
│       │   └── configmap.yaml   # Extra ConfigMap deployed alongside podinfo
│       ├── values.yaml          # Base values (default for all tenants)
│       ├── values-tenant-1.yaml # Tenant 1 overrides
│       └── values-tenant-2.yaml # Tenant 2 overrides
├── tenants-kustomization/
│   ├── tenant-1.yaml            # Flux GitRepository + Kustomization for tenant-1
│   ├── tenant-2.yaml            # Flux GitRepository + Kustomization for tenant-2
│   └── tenant-3.yaml            # Flux GitRepository + Kustomization for tenant-3
├── setup-clusters.sh            # Create kind clusters and install Flux
├── teardown-clusters.sh         # Delete all kind clusters
└── .gitignore
```

## How It Works

1. Flux watches this Git repo via a `GitRepository` source named `flux-sync`.
2. The `HelmRelease` in `gitops/podinfo.yaml` tells Flux to install the chart from `./helm-charts/podinfo`.
3. The `valuesFiles` field references `values-${tenantName}.yaml`. Flux replaces `${tenantName}` with the actual tenant name defined in each tenant's Flux Kustomization.
4. `ignoreMissingValuesFiles: true` means tenants without a dedicated values file fall back to base `values.yaml` only.

### Base vs Tenant Values

| File | replicaCount | ui.message | enabled |
|------|-------------|------------|---------|
| values.yaml (base) | 1 | "Hello from base values" | true |
| values-tenant-1.yaml | 10 | "Hello from tenant-1" | false |
| values-tenant-2.yaml | 5 | "Hello from tenant-2" | true |

## Prerequisites

- A Kubernetes cluster (or use the local kind setup below)
- Flux CD installed on the cluster
- `kubectl` and `flux` CLI tools

For local development with kind:

- Docker
- [kind](https://kind.sigs.k8s.io/)
- `helm`

## Local Development (kind)

Use the helper scripts to spin up three isolated kind clusters (`tenant-1`, `tenant-2`, `tenant-3`), each with Flux installed.

### Setup

```bash
./setup-clusters.sh
```

This script:

1. Creates kind clusters for all tenants (skips any that already exist)
2. Installs the Flux Operator via Helm on each cluster
3. Deploys a `FluxInstance` with all Flux controllers

Then apply the tenant Flux config on each cluster:

```bash
kubectl config use-context kind-tenant-1 && kubectl apply -f tenants-kustomization/tenant-1.yaml
kubectl config use-context kind-tenant-2 && kubectl apply -f tenants-kustomization/tenant-2.yaml
kubectl config use-context kind-tenant-3 && kubectl apply -f tenants-kustomization/tenant-3.yaml
```

Switch between clusters:

```bash
kubectl config use-context kind-tenant-1
kubectl config use-context kind-tenant-2
kubectl config use-context kind-tenant-3
```

### Teardown

Delete all kind clusters created by the setup script:

```bash
./teardown-clusters.sh
```

Skip the confirmation prompt:

```bash
./teardown-clusters.sh --force
```

Deleting a kind cluster removes all workloads, Flux controllers, and Helm releases inside it — no separate cleanup is needed.

## Manual Setup

### 1. Bootstrap Flux on your cluster

If Flux is not already running:

```bash
flux install
```

### 2. Create the GitRepository source

Point Flux at this repo:

```bash
flux create source git flux-sync \
  --url=https://github.com/sohel2020/flux-values-override-demo \
  --branch=main \
  --interval=1m
```

### 3. Create a Flux Kustomization for a tenant

Each tenant needs its own Flux Kustomization with `tenantName` substituted in.

For tenant-1:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant-1
  namespace: flux-system
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-sync
  path: ./gitops
  prune: true
  targetNamespace: tenant-1
  postBuild:
    substitute:
      tenantName: "tenant-1"
```

Apply it:

```bash
kubectl apply -f tenant-1.yaml
```

Repeat for tenant-2 (change `tenantName` to `tenant-2` and `targetNamespace` to `tenant-2`).

### 4. Verify the deployment

```bash
flux get kustomizations
flux get helmreleases -A
kubectl get pods -n tenant-1
kubectl get pods -n tenant-2
```

### 5. Add a new tenant

1. Create `helm-charts/podinfo/values-tenant-3.yaml` with your overrides.
2. Create a new Flux Kustomization with `tenantName: "tenant-3"`.
3. Commit and push. Flux picks it up automatically.

If you skip step 1, the tenant still works because `ignoreMissingValuesFiles: true` falls back to base values.
