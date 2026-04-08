#!/usr/bin/env bash
set -euo pipefail

# Opens ArgoCD UI via port-forward for a selected cluster

ARGOCD_NAMESPACE="argocd"
LOCAL_PORT=8080

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── pick cluster ──────────────────────────────
pick_cluster() {
  # accept cluster name as argument
  if [[ -n "${1:-}" ]]; then
    CLUSTER_NAME="$1"
    return
  fi

  local profiles=()
  while IFS= read -r p; do
    profiles+=("$p")
  done < <(minikube profile list -o json 2>/dev/null \
    | grep '"Name"' | awk -F'"' '{print $4}' | sort)

  if [[ ${#profiles[@]} -eq 0 ]]; then
    echo "No minikube clusters found. Run ./setup.sh first."
    exit 1
  fi

  if [[ ${#profiles[@]} -eq 1 ]]; then
    CLUSTER_NAME="${profiles[0]}"
    echo -e "Using cluster: ${BOLD}${CLUSTER_NAME}${NC}"
    return
  fi

  echo -e "\n${BOLD}${CYAN}── Select Cluster ──────────────────────────${NC}"
  for i in "${!profiles[@]}"; do
    local state
    state=$(minikube status -p "${profiles[$i]}" --format='{{.Host}}' 2>/dev/null || echo "Unknown")
    printf "  ${CYAN}[%d]${NC} %-20s (%s)\n" $((i+1)) "${profiles[$i]}" "$state"
  done
  echo ""
  read -r -p "  Choose cluster [1-${#profiles[@]}]: " choice

  if [[ "$choice" -lt 1 || "$choice" -gt ${#profiles[@]} ]] 2>/dev/null; then
    echo "Invalid choice."; exit 1
  fi
  CLUSTER_NAME="${profiles[$((choice-1))]}"
}

pick_cluster "${1:-}"

kubectl config use-context "$CLUSTER_NAME"

pkill -f "kubectl port-forward.*${LOCAL_PORT}" 2>/dev/null || true

echo -e "${GREEN}Starting port-forward → https://localhost:${LOCAL_PORT}${NC}"
kubectl port-forward svc/argocd-server \
  -n "$ARGOCD_NAMESPACE" \
  "${LOCAL_PORT}:443" &

sleep 2

PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n "$ARGOCD_NAMESPACE" \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo -e "${GREEN}Cluster    : ${CLUSTER_NAME}${NC}"
echo -e "${GREEN}ArgoCD UI  : https://localhost:${LOCAL_PORT}${NC}"
echo -e "${GREEN}Username   : admin${NC}"
echo -e "${GREEN}Password   : ${PASSWORD}${NC}"
echo ""
echo "Press Ctrl+C to stop port-forward."
wait
