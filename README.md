# testcloud-local

Local Kubernetes environment that mimics AWS EKS — powered by **minikube** and **ArgoCD**.

Use it to develop, test, and validate workloads locally before deploying to a real EKS cluster.

---

## Requirements

| Tool | Install |
|---|---|
| `minikube` | `brew install minikube` |
| `kubectl` | `brew install kubectl` |
| `helm` | `brew install helm` |
| `gh` | `brew install gh` _(optional, for GitHub ops)_ |

A driver is also required. See [Drivers](#drivers) below.

---

## Quick Start

```bash
git clone https://github.com/krypob/testcloud-local.git
cd testcloud-local
./setup.sh
```

The setup wizard will walk you through every option interactively.

---

## Scripts

### `setup.sh` — Bootstrap the cluster

Starts minikube and installs ArgoCD. Fully interactive — asks for every option before starting.

```bash
./setup.sh
```

**What it does, step by step:**

1. Checks that `minikube`, `kubectl`, and `helm` are installed
2. Asks which Kubernetes version to use (EKS-compatible list)
3. Asks how many CPUs to allocate (auto-detects your machine's total)
4. Asks how much Memory to allocate in MB (auto-detects available RAM)
5. Asks how much Disk space to allocate (shows free space on host)
6. Asks which driver to use (shows install status for each)
7. If the chosen driver is missing — offers to install it via Homebrew automatically
8. Shows a configuration summary and asks for confirmation
9. Starts the minikube cluster
10. Creates base namespaces: `argocd`, `apps`, `infra`, `monitoring`
11. Installs ArgoCD and waits for it to be ready
12. Prints the ArgoCD admin password

---

### `access.sh` — Open the ArgoCD UI

Port-forwards ArgoCD to `https://localhost:8080` and prints credentials.

```bash
./access.sh
```

```
ArgoCD UI  : https://localhost:8080
Username   : admin
Password   : <printed here>
```

Press `Ctrl+C` to stop the port-forward.

---

### `teardown.sh` — Destroy the cluster

Deletes the minikube cluster. Asks for confirmation before doing anything.

```bash
./teardown.sh
```

---

### `Makefile` — Shortcuts

```bash
make setup      # run setup.sh
make access     # run access.sh
make teardown   # run teardown.sh
make status     # show cluster status + ArgoCD pods
```

---

## Configuration Options

All options are chosen interactively during `setup.sh`. Here is what you can configure:

### Kubernetes Version

EKS-compatible versions selectable from a menu:

| Option | Version | Status |
|---|---|---|
| 1 | `v1.32.0` | EKS latest |
| 2 | `v1.31.0` | EKS stable |
| 3 | `v1.30.0` | EKS stable, LTS candidate _(default)_ |
| 4 | `v1.29.0` | EKS stable |
| 5 | `v1.28.0` | EKS extended support |
| 6 | `v1.27.0` | EKS extended support |

### Resources

| Setting | Default | Notes |
|---|---|---|
| CPUs | `4` | Capped to machine total |
| Memory | `8192` MB | Capped to available RAM |
| Disk | `40g` | Format: `20g`, `50g`, `100g`, etc. |

### Drivers

| Driver | Weight | Notes |
|---|---|---|
| `docker` | Medium | Most compatible. Requires Docker Desktop. Cannot be auto-installed. |
| `podman` | Light | Rootless, no daemon. Auto-installed via `brew install podman`. |
| `qemu2` | Light | Best for Apple Silicon (M1/M2/M3). Auto-installed via `brew install qemu`. |
| `hyperkit` | Light | macOS Intel only. Deprecated. Auto-installed via `brew install hyperkit`. |

If a driver is not installed, `setup.sh` will offer to install it automatically (except Docker Desktop, which must be installed manually).

---

## Namespaces

The following namespaces are created automatically:

| Namespace | Purpose |
|---|---|
| `argocd` | ArgoCD system components |
| `apps` | Your application workloads |
| `infra` | Infrastructure components (ingress, cert-manager, etc.) |
| `monitoring` | Observability stack (Prometheus, Grafana, etc.) |

---

## Minikube Addons

Enabled by default:

| Addon | Purpose |
|---|---|
| `ingress` | NGINX ingress controller |
| `metrics-server` | CPU/memory metrics for `kubectl top` |
| `dashboard` | Kubernetes web UI |

Access the Kubernetes dashboard:

```bash
minikube dashboard --profile=testcloud
```

---

## ArgoCD

ArgoCD is installed in the `argocd` namespace using the official manifests.

### Login via CLI

```bash
# get the password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

# login
argocd login localhost:8080 --username admin --insecure
```

### Deploy an app with ArgoCD

```bash
argocd app create my-app \
  --repo https://github.com/your-org/your-repo.git \
  --path helm/my-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace apps \
  --sync-policy automated
```

---

## Multiple Clusters

You can run `setup.sh` multiple times with different names to create independent clusters — e.g. one per project or one per Kubernetes version.

```bash
./setup.sh          # prompted for name, e.g. "staging"
./setup.sh          # run again, e.g. "prod-test"
```

`access.sh` and `teardown.sh` will show a menu to pick which cluster to target when more than one exists. You can also pass the name directly:

```bash
./access.sh staging
./teardown.sh prod-test
```

Or with make:
```bash
make access   CLUSTER=staging
make teardown CLUSTER=prod-test
```

---

## Cluster Management

```bash
# list all clusters and their state
minikube profile list

# stop a cluster (preserves state)
minikube stop --profile=<name>

# start it again
minikube start --profile=<name>

# check status
minikube status --profile=<name>

# SSH into the node
minikube ssh --profile=<name>
```

---

## Tips

- **Stopping vs deleting** — `minikube stop` pauses the cluster and saves state. `teardown.sh` (or `minikube delete`) removes it entirely.
- **Multiple clusters** — minikube supports multiple profiles. Edit `CLUSTER_NAME` in `setup.sh` to run a second environment in parallel.
- **Matching EKS** — pick the same `K8S_VERSION` as your target EKS cluster to catch version-specific issues locally.
- **Low on resources?** — 2 CPUs and 4096 MB RAM is enough to run the cluster with ArgoCD. Scale up if you add more workloads.
