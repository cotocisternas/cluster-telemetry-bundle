# cluster-telemetry-bundle local operations.
.DEFAULT_GOAL := help

AQUA ?= aqua
DOCKER ?= docker
KIND ?= $(AQUA) exec -- kind
KUBECTL ?= $(AQUA) exec -- kubectl
HELM ?= $(AQUA) exec -- helm
FLUX ?= $(AQUA) exec -- flux

E2E_KIND_CLUSTER ?= cluster-telemetry-bundle-e2e
E2E_KIND_CONTEXT ?= kind-$(E2E_KIND_CLUSTER)
E2E_KIND_CONFIG ?= test/e2e/kind/cluster-cilium.yaml
E2E_OVERLAY ?= test/e2e/overlays/kind-cilium
E2E_ARTIFACT_DIR ?= artifacts/kind

CILIUM_VERSION ?= 1.19.4
CILIUM_VALUES ?= test/e2e/cilium/values.yaml
CILIUM_MONITORING_VALUES ?= base/components/cilium-hubble-monitoring/values.yaml
CILIUM_SCRIPT ?= scripts/e2e-kind-cilium.sh

PROMETHEUS_OPERATOR_VERSION ?= v0.91.0
PROMETHEUS_OPERATOR_CRD_BASE ?= https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/refs/tags/$(PROMETHEUS_OPERATOR_VERSION)/example/prometheus-operator-crd

.PHONY: help
help:
	@printf 'Targets:\n'
	@printf '  make tools-install        Install pinned CLIs through aqua\n'
	@printf '  make tools-check          Verify aqua-managed CLIs are usable\n'
	@printf '  make manifests-check       Render all Kustomize entrypoints\n'
	@printf '  make e2e-kind-static-check Check Kind/Cilium harness invariants\n'
	@printf '  make e2e-kind-up           Create Kind, install Cilium/Flux, deploy bundle, run checks\n'
	@printf '  make e2e-kind-check        Check an existing Kind environment\n'
	@printf '  make e2e-kind-artifacts    Collect diagnostics from an existing Kind environment\n'
	@printf '  make e2e-kind-delete       Delete the Kind environment\n'

.PHONY: check
check: tools-check manifests-check e2e-kind-static-check

.PHONY: tools-install
tools-install:
	$(AQUA) install

.PHONY: tools-check
tools-check:
	@command -v "$(AQUA)" >/dev/null 2>&1 || { printf 'missing required tool manager: aqua\nInstall aqua first, then run make tools-install.\n' >&2; exit 1; }
	@$(KIND) version >/dev/null
	@$(KUBECTL) version --client=true >/dev/null
	@$(HELM) version --short >/dev/null
	@$(FLUX) --version >/dev/null

.PHONY: e2e-kind-host-check
e2e-kind-host-check: tools-check
	@command -v "$(DOCKER)" >/dev/null 2>&1 || { printf 'missing required container runtime CLI: docker\n' >&2; exit 1; }
	@$(DOCKER) info >/dev/null

.PHONY: manifests-check
manifests-check: tools-check
	$(KUBECTL) kustomize base >/dev/null
	$(KUBECTL) kustomize examples/cluster-us-east-1 >/dev/null
	$(KUBECTL) kustomize examples/cluster-us-east-1-prometheus-crds >/dev/null
	$(KUBECTL) kustomize examples/cluster-us-east-1-monitoring-bundle >/dev/null
	$(KUBECTL) kustomize examples/flux/core >/dev/null
	$(KUBECTL) kustomize examples/flux/prometheus-crds >/dev/null
	$(KUBECTL) kustomize examples/flux/monitoring-bundle >/dev/null
	$(KUBECTL) kustomize $(E2E_OVERLAY) >/dev/null

.PHONY: e2e-kind-static-check
e2e-kind-static-check:
	@sh scripts/check-e2e-kind.sh

.PHONY: e2e-kind-create
e2e-kind-create:
	$(KIND) create cluster --name "$(E2E_KIND_CLUSTER)" --config "$(E2E_KIND_CONFIG)"

.PHONY: e2e-kind-ensure
e2e-kind-ensure: e2e-kind-host-check
	@if $(KIND) get clusters 2>/dev/null | grep -Fx "$(E2E_KIND_CLUSTER)" >/dev/null 2>&1; then \
		printf 'kind cluster already exists: %s\n' "$(E2E_KIND_CLUSTER)"; \
	else \
		$(KIND) create cluster --name "$(E2E_KIND_CLUSTER)" --config "$(E2E_KIND_CONFIG)"; \
	fi
	$(KIND) export kubeconfig --name "$(E2E_KIND_CLUSTER)" >/dev/null
	$(MAKE) e2e-kind-prometheus-crds
	$(MAKE) e2e-kind-cilium-install
	$(MAKE) e2e-kind-cilium-wait
	$(MAKE) e2e-kind-flux-install

.PHONY: e2e-kind-prometheus-crds
e2e-kind-prometheus-crds:
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" apply --server-side -f "$(PROMETHEUS_OPERATOR_CRD_BASE)/monitoring.coreos.com_servicemonitors.yaml"
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" apply --server-side -f "$(PROMETHEUS_OPERATOR_CRD_BASE)/monitoring.coreos.com_podmonitors.yaml"
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" wait --for=condition=Established crd/servicemonitors.monitoring.coreos.com --timeout=60s
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" wait --for=condition=Established crd/podmonitors.monitoring.coreos.com --timeout=60s

.PHONY: e2e-kind-cilium-install
e2e-kind-cilium-install:
	E2E_KIND_CLUSTER="$(E2E_KIND_CLUSTER)" \
		E2E_KIND_CONTEXT="$(E2E_KIND_CONTEXT)" \
		CILIUM_VERSION="$(CILIUM_VERSION)" \
		CILIUM_VALUES="$(CILIUM_VALUES)" \
		CILIUM_MONITORING_VALUES="$(CILIUM_MONITORING_VALUES)" \
		HELM="$(HELM)" \
		KUBECTL="$(KUBECTL)" \
		"$(CILIUM_SCRIPT)" install

.PHONY: e2e-kind-cilium-wait
e2e-kind-cilium-wait:
	E2E_KIND_CLUSTER="$(E2E_KIND_CLUSTER)" \
		E2E_KIND_CONTEXT="$(E2E_KIND_CONTEXT)" \
		KUBECTL="$(KUBECTL)" \
		"$(CILIUM_SCRIPT)" wait

.PHONY: e2e-kind-flux-install
e2e-kind-flux-install:
	$(FLUX) install --context "$(E2E_KIND_CONTEXT)"
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" -n flux-system rollout status deployment/source-controller --timeout=180s
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" -n flux-system rollout status deployment/kustomize-controller --timeout=180s
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" -n flux-system rollout status deployment/helm-controller --timeout=180s

.PHONY: e2e-kind-deploy
e2e-kind-deploy: manifests-check
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" apply -k "$(E2E_OVERLAY)"

.PHONY: e2e-kind-check
e2e-kind-check:
	E2E_KIND_CLUSTER="$(E2E_KIND_CLUSTER)" \
		E2E_KIND_CONTEXT="$(E2E_KIND_CONTEXT)" \
		KUBECTL="$(KUBECTL)" \
		"$(CILIUM_SCRIPT)" doctor
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" -n telemetry wait helmrelease --all --for=condition=Ready --timeout=10m
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" -n telemetry wait pod --all --for=condition=Ready --timeout=5m
	$(KUBECTL) --context "$(E2E_KIND_CONTEXT)" get servicemonitor -A -l telemetry.example.com/scrape=true

.PHONY: e2e-kind-artifacts
e2e-kind-artifacts:
	ARTIFACT_DIR="$(E2E_ARTIFACT_DIR)" \
		KUBE_CONTEXT="$(E2E_KIND_CONTEXT)" \
		KUBECTL="$(KUBECTL)" \
		scripts/collect-kind-artifacts.sh

.PHONY: e2e-kind-up
e2e-kind-up: e2e-kind-ensure e2e-kind-deploy e2e-kind-check

.PHONY: e2e-kind-delete
e2e-kind-delete:
	$(KIND) delete cluster --name "$(E2E_KIND_CLUSTER)"
