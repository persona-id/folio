# app name must be lowercase
export APP_NAME ?= $(shell basename $(CURDIR) | tr '[:upper:]' '[:lower:]')
export HELM_DRIVER := configmap
# Dev deploys use a stable per-user namespace (frontier-<app>-dev-<user>).
# Set DEV_SUFFIX (e.g. DEV_SUFFIX=-foo make dev) only to run a second,
# isolated dev deploy in parallel with your default one.
export DEV_SUFFIX ?=

.PHONY: dev dev-debug dev-remote dev-render setup deploy-dev deploy-prod deploy-prod-remote dev-delete prod-delete login help status set-owner setup-context

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

login: ## Login to GHCR (required before first deploy)
	@gh auth status >/dev/null 2>&1 || gh auth login
	@gh auth refresh -s write:packages,repo
	@echo "Logging into GHCR..."
	@gh auth token | docker login ghcr.io -u $$(gh api user -q .login) --password-stdin
	@gh auth token | helm registry login ghcr.io -u $$(gh api user -q .login) --password-stdin

setup-context: ## Configure kubectl to connect to the Frontier cluster via Tailscale
	@if [ -z "$$CI" ]; then \
		tailscale configure kubeconfig https://frontier-us-central1-k8s-api; \
	fi

set-owner:
	@owner=$$(grep 'owner:' deploy/values.yaml | head -1 | awk '{print $$2}' | tr -d '"'"'"); \
	if [ -z "$$owner" ]; then \
		if [ -z "$$CI" ]; then \
			read -p "What is the Persona username of the Personerd that will be the primary owner of this app (<username> portion of <username>@withpersona.com)? " new_owner; \
			sed -i '' "s/owner:.*/owner: $$new_owner/" deploy/values.yaml; \
			echo "Updated deploy/values.yaml with owner: $$new_owner"; \
		else \
			echo "Error: owner is not set in deploy/values.yaml"; \
			exit 1; \
		fi; \
	else \
		echo "Owner already set to $$owner. Update the owner field in deploy/values.yaml if you want to change it."; \
	fi

dev: setup-context set-owner ## Deploy with file watching (local Docker builds)
	envsubst < skaffold.yaml >| /tmp/skaffold-dev.yaml && skaffold dev -f /tmp/skaffold-dev.yaml --cleanup=false

dev-debug: setup-context set-owner ## Deploy with file watching (debug mode)
	envsubst < skaffold.yaml >| /tmp/skaffold-dev.yaml && skaffold dev -f /tmp/skaffold-dev.yaml --cleanup=false -v debug

dev-remote: setup-context set-owner ## Deploy with file watching (remote Kaniko builds, no Docker needed)
	envsubst < skaffold.yaml >| /tmp/skaffold-dev.yaml && skaffold dev -f /tmp/skaffold-dev.yaml --cleanup=false -p dev-remote-build

dev-render: ## Render dev manifests without deploying
	envsubst < skaffold.yaml >| /tmp/skaffold-dev.yaml && skaffold render -f /tmp/skaffold-dev.yaml

setup: ## Installs required utilities locally to support running local development tools in the repo
	brew install kubectl skaffold gh tailscale
	@command -v docker >/dev/null 2>&1 || brew install orbstack

deploy-dev: setup-context set-owner ## Deploy once to the shared dev namespace (frontier-<app>-dev)
	envsubst < skaffold.yaml >| /tmp/skaffold-dev-once.yaml && skaffold run -f /tmp/skaffold-dev-once.yaml -p dev

deploy-prod: setup-context set-owner ## Deploy once to prod (local Docker builds)
	envsubst < skaffold.yaml >| /tmp/skaffold-prod.yaml && skaffold run -f /tmp/skaffold-prod.yaml -p prod

deploy-prod-remote: setup-context set-owner ## Deploy once to prod (remote Kaniko builds)
	envsubst < skaffold.yaml >| /tmp/skaffold-prod.yaml && skaffold run -f /tmp/skaffold-prod.yaml -p prod-remote-build

dev-delete: setup-context ## Delete the dev deployment (and any DEV_SUFFIX variants)
	@for ns in $$(kubectl get ns -o name 2>/dev/null | grep -E "^namespace/frontier-$(APP_NAME)-dev($$|-)" | cut -d/ -f2); do \
		echo "Deleting deployment in $$ns..."; \
		helm uninstall app -n $$ns 2>/dev/null || true; \
		suffix=$${ns#frontier-$(APP_NAME)-dev}; \
		helm uninstall bootstrap-$(APP_NAME)-dev$$suffix -n frontier-system 2>/dev/null || true; \
	done

prod-delete: setup-context ## Delete the prod deployment
	helm uninstall app -n frontier-$(APP_NAME)-prod || true
	helm uninstall bootstrap-$(APP_NAME)-prod -n frontier-system || true

status: ## Show deployment status
	@kubectl get ksvc -n frontier-$(APP_NAME) 2>/dev/null || echo "No Knative service found"
	@kubectl get domainmapping -n frontier-$(APP_NAME) 2>/dev/null || echo "No DomainMapping found"
	@kubectl get pods -n frontier-$(APP_NAME) 2>/dev/null || echo "No pods found"
