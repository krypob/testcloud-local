#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="testcloud"

RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${YELLOW}This will DELETE the minikube cluster '${CLUSTER_NAME}'.${NC}"
read -r -p "Are you sure? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }

pkill -f "kubectl port-forward" 2>/dev/null || true

minikube delete --profile="$CLUSTER_NAME"
echo -e "${RED}Cluster '${CLUSTER_NAME}' deleted.${NC}"
