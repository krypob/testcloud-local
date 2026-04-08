#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

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
    echo "No minikube clusters found. Nothing to teardown."
    exit 0
  fi

  if [[ ${#profiles[@]} -eq 1 ]]; then
    CLUSTER_NAME="${profiles[0]}"
    return
  fi

  echo -e "\n${BOLD}${CYAN}── Select Cluster to Delete ────────────────${NC}"
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

echo -e "${YELLOW}This will DELETE the minikube cluster '${CLUSTER_NAME}'.${NC}"
read -r -p "Are you sure? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }

pkill -f "kubectl port-forward" 2>/dev/null || true

minikube delete --profile="$CLUSTER_NAME"
echo -e "${RED}Cluster '${CLUSTER_NAME}' deleted.${NC}"
