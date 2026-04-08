#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# testcloud-local — local EKS-like env
# minikube + ArgoCD
# ──────────────────────────────────────────────

ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="v2.10.4"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }

# ── select cluster name ───────────────────────
select_cluster_name() {
  header "── Cluster Name ────────────────────────────"

  # list existing minikube profiles
  local existing
  existing=$(minikube profile list -o json 2>/dev/null \
    | grep '"Name"' | awk -F'"' '{print $4}' | sort) || existing=""

  if [[ -n "$existing" ]]; then
    echo "  Existing clusters on this machine:"
    while IFS= read -r p; do
      local state
      state=$(minikube status -p "$p" --format='{{.Host}}' 2>/dev/null || echo "Unknown")
      printf "    • %-20s (%s)\n" "$p" "$state"
    done <<< "$existing"
    echo ""
  fi

  read -r -p "  Cluster name (default: testcloud): " name_input
  CLUSTER_NAME="${name_input:-testcloud}"

  # only allow alphanumeric + dash
  if ! [[ "$CLUSTER_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    warn "Invalid name '${CLUSTER_NAME}' — only letters, numbers, and hyphens allowed. Using 'testcloud'."
    CLUSTER_NAME="testcloud"
  fi

  if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
    warn "Cluster '${CLUSTER_NAME}' already exists and is running."
    read -r -p "  Continue anyway and skip cluster creation? (yes/no): " skip
    if [[ "$skip" != "yes" ]]; then
      echo "Aborted. Choose a different name or teardown the existing cluster first."
      exit 0
    fi
  fi

  info "Cluster name: ${CLUSTER_NAME}"
}

# ── dependency check ──────────────────────────
check_deps() {
  info "Checking dependencies..."
  local missing=()
  for cmd in minikube kubectl helm; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing tools: ${missing[*]}\nInstall them and re-run."
  fi
  info "All dependencies found."
}

# ── select kubernetes version ─────────────────
# EKS supported versions: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
select_k8s_version() {
  header "── Kubernetes Version ──────────────────────"
  echo "  EKS-compatible versions available:"
  echo ""

  local versions=(
    "v1.32.0   (EKS latest, released Jan 2025)"
    "v1.31.0   (EKS stable)"
    "v1.30.0   (EKS stable, LTS candidate)"
    "v1.29.0   (EKS stable)"
    "v1.28.0   (EKS extended support)"
    "v1.27.0   (EKS extended support)"
  )
  local version_ids=("v1.32.0" "v1.31.0" "v1.30.0" "v1.29.0" "v1.28.0" "v1.27.0")

  for i in "${!versions[@]}"; do
    printf "  ${CYAN}[%d]${NC} %s\n" $((i+1)) "${versions[$i]}"
  done

  echo ""
  read -r -p "  Choose version [1-${#versions[@]}] (default: 3 → v1.30.0): " choice
  choice=${choice:-3}

  if [[ "$choice" -lt 1 || "$choice" -gt ${#versions[@]} ]] 2>/dev/null; then
    warn "Invalid choice, using default v1.30.0"
    K8S_VERSION="v1.30.0"
  else
    K8S_VERSION="${version_ids[$((choice-1))]}"
  fi

  info "Selected Kubernetes version: ${K8S_VERSION}"
}

# ── select resources ──────────────────────────
select_resources() {
  local total_cpus total_mem_mb

  # detect available resources
  total_cpus=$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)
  total_mem_mb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 8589934592) / 1024 / 1024 ))

  header "── CPU ─────────────────────────────────────"
  echo "  Available CPUs on this machine: ${total_cpus}"
  echo "  Recommended: leave at least 2 CPUs for the host"
  echo ""
  read -r -p "  CPUs to allocate (default: 4): " cpu_input
  CPUS=${cpu_input:-4}

  if [[ "$CPUS" -gt "$total_cpus" ]]; then
    warn "Requested ${CPUS} CPUs but only ${total_cpus} available — capping to ${total_cpus}."
    CPUS=$total_cpus
  fi

  header "── Memory ──────────────────────────────────"
  echo "  Available RAM on this machine: ${total_mem_mb} MB  (~$(( total_mem_mb / 1024 )) GB)"
  echo "  Recommended: leave at least 4096 MB (4 GB) for the host"
  echo ""
  read -r -p "  Memory to allocate in MB (default: 8192): " mem_input
  MEMORY=${mem_input:-8192}

  if [[ "$MEMORY" -gt "$total_mem_mb" ]]; then
    warn "Requested ${MEMORY} MB but only ${total_mem_mb} MB available — capping."
    MEMORY=$(( total_mem_mb - 4096 ))
  fi

  header "── Disk ────────────────────────────────────"
  local free_gb
  free_gb=$(df -g / 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")
  echo "  Free disk space on host: ~${free_gb} GB"
  echo "  Enter size with unit: e.g. 20g, 50g, 100g"
  echo "  Recommended minimum: 20g"
  echo ""
  read -r -p "  Disk size to allocate (default: 40g): " disk_input
  DISK=${disk_input:-40g}

  # basic validation — must match <number>g or <number>G
  if ! [[ "$DISK" =~ ^[0-9]+[gG]$ ]]; then
    warn "Invalid format '${DISK}', using default 40g."
    DISK="40g"
  fi

  info "Resources set: CPUs=${CPUS}, Memory=${MEMORY} MB, Disk=${DISK}"
}

# ── check if a driver binary is present ───────
driver_available() {
  case "$1" in
    docker)   command -v docker &>/dev/null ;;
    podman)   command -v podman &>/dev/null ;;
    qemu2)    command -v qemu-system-aarch64 &>/dev/null || command -v qemu-system-x86_64 &>/dev/null ;;
    hyperkit) command -v hyperkit &>/dev/null ;;
  esac
}

driver_install() {
  local driver="$1"
  command -v brew &>/dev/null || error "Homebrew not found. Install it from https://brew.sh then re-run."

  case "$driver" in
    docker)
      warn "Docker Desktop cannot be installed automatically."
      warn "Download it from: https://www.docker.com/products/docker-desktop"
      error "Install Docker Desktop manually and re-run setup."
      ;;
    podman)
      info "Installing podman via Homebrew..."
      brew install podman
      info "Initialising podman machine..."
      podman machine init 2>/dev/null || true
      podman machine start 2>/dev/null || true
      ;;
    qemu2)
      info "Installing qemu via Homebrew..."
      brew install qemu
      ;;
    hyperkit)
      info "Installing hyperkit via Homebrew..."
      brew install hyperkit
      ;;
  esac
}

# ── select driver ─────────────────────────────
select_driver() {
  header "── Driver ──────────────────────────────────"

  local drivers=("docker" "podman" "qemu2" "hyperkit")
  local labels=(
    "docker    — standard, most compatible, requires Docker Desktop/Engine"
    "podman    — rootless, daemonless — lighter than Docker, no daemon overhead"
    "qemu2     — lightweight VM, best for Apple Silicon, no Docker needed"
    "hyperkit  — lightweight VM (macOS Intel only, deprecated)"
  )

  echo "  Available drivers:"
  echo ""
  for i in "${!drivers[@]}"; do
    local status
    if driver_available "${drivers[$i]}"; then
      status="${GREEN}✔ installed${NC}"
    else
      status="${RED}✘ not found${NC}"
    fi
    printf "  ${CYAN}[%d]${NC} %-50s %b\n" $((i+1)) "${labels[$i]}" "$status"
  done

  echo ""
  echo "  Lightweight pick:"
  echo "    • Apple Silicon (M1/M2/M3) → qemu2 or podman"
  echo "    • Intel Mac                → podman or docker"
  echo ""
  read -r -p "  Choose driver [1-4] (default: 1 → docker): " choice
  choice=${choice:-1}

  case "$choice" in
    1) DRIVER="docker" ;;
    2) DRIVER="podman" ;;
    3) DRIVER="qemu2" ;;
    4) DRIVER="hyperkit" ;;
    *) warn "Invalid choice, using docker"; DRIVER="docker" ;;
  esac

  if ! driver_available "$DRIVER"; then
    echo ""
    warn "Driver '${DRIVER}' is not installed."
    read -r -p "  Install '${DRIVER}' now? (yes/no): " install_confirm
    if [[ "$install_confirm" == "yes" ]]; then
      driver_install "$DRIVER"
      if ! driver_available "$DRIVER"; then
        error "Installation of '${DRIVER}' failed or requires a shell restart. Re-run setup."
      fi
      info "Driver '${DRIVER}' installed successfully."
    else
      error "Driver '${DRIVER}' is required. Install it and re-run setup."
    fi
  fi

  info "Selected driver: ${DRIVER}"
}

# ── minikube ──────────────────────────────────
start_minikube() {
  if minikube status -p "$CLUSTER_NAME" &>/dev/null; then
    warn "Cluster '$CLUSTER_NAME' already running — skipping creation."
    return
  fi

  info "Starting minikube cluster '$CLUSTER_NAME'..."
  minikube start \
    --profile="$CLUSTER_NAME" \
    --kubernetes-version="$K8S_VERSION" \
    --driver="$DRIVER" \
    --cpus="$CPUS" \
    --memory="$MEMORY" \
    --disk-size="$DISK" \
    --addons=ingress,metrics-server,dashboard \
    --extra-config=apiserver.authorization-mode=Node,RBAC

  info "Setting kubectl context to '$CLUSTER_NAME'..."
  kubectl config use-context "$CLUSTER_NAME"
}

# ── namespaces ────────────────────────────────
create_namespaces() {
  info "Creating base namespaces..."
  for ns in "$ARGOCD_NAMESPACE" apps infra monitoring; do
    kubectl get namespace "$ns" &>/dev/null \
      || kubectl create namespace "$ns"
  done
}

# ── argocd ────────────────────────────────────
install_argocd() {
  if kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" &>/dev/null; then
    warn "ArgoCD already installed — skipping."
    return
  fi

  info "Installing ArgoCD ${ARGOCD_VERSION}..."
  kubectl apply -n "$ARGOCD_NAMESPACE" \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

  info "Waiting for ArgoCD pods to be ready..."
  kubectl wait --for=condition=available deployment \
    --all -n "$ARGOCD_NAMESPACE" --timeout=180s
}

# ── argocd access ─────────────────────────────
configure_argocd_access() {
  kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" \
    -p '{"spec": {"type": "NodePort"}}' &>/dev/null

  local password
  password=$(kubectl get secret argocd-initial-admin-secret \
    -n "$ARGOCD_NAMESPACE" \
    -o jsonpath="{.data.password}" | base64 -d)

  echo ""
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ArgoCD ready!${NC}"
  echo -e "${GREEN}  Username : admin${NC}"
  echo -e "${GREEN}  Password : ${password}${NC}"
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  echo ""
  info "Run './access.sh' to open the ArgoCD UI."
}

# ── summary ───────────────────────────────────
print_summary() {
  header "── Configuration Summary ───────────────────"
  printf "  %-12s %s\n" "Cluster:"    "$CLUSTER_NAME"
  printf "  %-12s %s\n" "K8s:"        "$K8S_VERSION"
  printf "  %-12s %s\n" "Driver:"     "$DRIVER"
  printf "  %-12s %s\n" "CPUs:"       "$CPUS"
  printf "  %-12s %s MB\n" "Memory:"  "$MEMORY"
  printf "  %-12s %s\n" "Disk:"       "$DISK"
  echo ""
  read -r -p "  Proceed with this configuration? (yes/no): " confirm
  [[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }
}

# ── main ──────────────────────────────────────
main() {
  echo -e "${BOLD}${CYAN}"
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║     testcloud-local  setup           ║"
  echo "  ║     minikube + ArgoCD (EKS-like)     ║"
  echo "  ╚══════════════════════════════════════╝"
  echo -e "${NC}"

  check_deps
  select_cluster_name
  select_k8s_version
  select_resources
  select_driver
  print_summary
  start_minikube
  create_namespaces
  install_argocd
  configure_argocd_access
  info "Setup complete."
}

main "$@"
