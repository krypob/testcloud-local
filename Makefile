.PHONY: setup access teardown status

setup:
	@bash setup.sh

access:
	@bash access.sh $(CLUSTER)

teardown:
	@bash teardown.sh $(CLUSTER)

status:
	@minikube profile list
	@echo ""
	@kubectl get pods -n argocd 2>/dev/null || echo "No active kubectl context."
