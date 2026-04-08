#!/usr/bin/env bash
set -euo pipefail

# Opens ArgoCD UI via port-forward in the background

CLUSTER_NAME="testcloud"
ARGOCD_NAMESPACE="argocd"
LOCAL_PORT=8080

GREEN='\033[0;32m'; NC='\033[0m'

kubectl config use-context "$CLUSTER_NAME"

# Kill any existing port-forward on the same port
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
echo -e "${GREEN}ArgoCD UI  : https://localhost:${LOCAL_PORT}${NC}"
echo -e "${GREEN}Username   : admin${NC}"
echo -e "${GREEN}Password   : ${PASSWORD}${NC}"
echo ""
echo "Press Ctrl+C to stop port-forward."
wait
