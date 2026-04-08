.PHONY: setup access teardown status

setup:
	@bash setup.sh

access:
	@bash access.sh

teardown:
	@bash teardown.sh

status:
	@minikube status --profile=testcloud
	@echo ""
	@kubectl get pods -n argocd
