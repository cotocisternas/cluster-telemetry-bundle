#!/usr/bin/env sh
set -eu

KIND_CONFIG=${E2E_KIND_CONFIG:-test/e2e/kind/cluster-cilium.yaml}
E2E_OVERLAY=${E2E_OVERLAY:-test/e2e/overlays/kind-cilium}
CILIUM_VALUES=${CILIUM_VALUES:-test/e2e/cilium/values.yaml}
CILIUM_MONITORING_VALUES=${CILIUM_MONITORING_VALUES:-base/components/cilium-hubble-monitoring/values.yaml}
CILIUM_SCRIPT=${CILIUM_SCRIPT:-scripts/e2e-kind-cilium.sh}
MAKEFILE=${MAKEFILE:-Makefile}
AQUA_CONFIG=${AQUA_CONFIG:-aqua.yaml}

require_file() {
	path=$1
	description=$2

	if [ ! -f "$path" ]; then
		echo "e2e kind check failed: missing $description at $path" >&2
		exit 1
	fi
}

require() {
	pattern=$1
	file=$2
	description=$3

	if ! grep -Eq "$pattern" "$file"; then
		echo "e2e kind check failed: missing $description in $file" >&2
		exit 1
	fi
}

reject() {
	pattern=$1
	file=$2
	description=$3

	if grep -Eq "$pattern" "$file"; then
		echo "e2e kind check failed: found $description in $file" >&2
		exit 1
	fi
}

require_file "$KIND_CONFIG" "Kind Cilium cluster config"
require_file "$AQUA_CONFIG" "aqua toolchain config"
require_file "$E2E_OVERLAY/kustomization.yaml" "Kind Cilium Kustomize overlay"
require_file "$E2E_OVERLAY/otel-values.yaml" "Kind Cilium OTel values"
require_file "$CILIUM_VALUES" "Kind Cilium Helm values"
require_file "$CILIUM_MONITORING_VALUES" "Cilium/Hubble monitoring values"
require_file "$CILIUM_SCRIPT" "Cilium helper script"
require_file "scripts/collect-kind-artifacts.sh" "Kind artifact collector"

require 'disableDefaultCNI:[[:space:]]*true' "$KIND_CONFIG" "disabled Kind default CNI"
require 'kubeProxyMode:[[:space:]]*"?none"?' "$KIND_CONFIG" "disabled kube-proxy"
require 'role:[[:space:]]*control-plane' "$KIND_CONFIG" "control-plane node"
require 'role:[[:space:]]*worker' "$KIND_CONFIG" "worker nodes"

require 'type:[[:space:]]*standard' "$AQUA_CONFIG" "aqua standard registry"
require 'ref:[[:space:]]*v4\.520\.0' "$AQUA_CONFIG" "pinned aqua registry"
require 'kubernetes-sigs/kind@v0\.31\.0' "$AQUA_CONFIG" "pinned kind"
require 'kubernetes/kubernetes/kubectl@v1\.36\.1' "$AQUA_CONFIG" "pinned kubectl"
require 'helm/helm@v3\.21\.0' "$AQUA_CONFIG" "pinned Helm 3"
require 'fluxcd/flux2@v2\.8\.8' "$AQUA_CONFIG" "pinned Flux"

require 'kubeProxyReplacement:[[:space:]]*true' "$CILIUM_VALUES" "Cilium kube-proxy replacement"
require 'mode:[[:space:]]*kubernetes' "$CILIUM_VALUES" "Cilium Kubernetes IPAM"
require 'enabled:[[:space:]]*true' "$CILIUM_VALUES" "Cilium NodePort support"
reject 'k8sServiceHost:' "$CILIUM_VALUES" "static Kubernetes API host"

require 'prometheus:' "$CILIUM_MONITORING_VALUES" "Cilium metrics"
require 'hubble:' "$CILIUM_MONITORING_VALUES" "Hubble metrics"
require 'relay:' "$CILIUM_MONITORING_VALUES" "Hubble Relay metrics"
require 'enableOpenMetrics:[[:space:]]*true' "$CILIUM_MONITORING_VALUES" "Hubble OpenMetrics"
require 'telemetry\.example\.com/scrape:[[:space:]]*"true"' "$CILIUM_MONITORING_VALUES" "Target Allocator selector labels"
require 'serviceMonitor:' "$CILIUM_MONITORING_VALUES" "Cilium ServiceMonitor hooks"

require 'cluster-us-east-1-monitoring-bundle' "$E2E_OVERLAY/kustomization.yaml" "full monitoring bundle reuse"
require 'cilium-hubble-monitoring' "$E2E_OVERLAY/kustomization.yaml" "Cilium monitoring values profile"
require 'behavior:[[:space:]]*replace' "$E2E_OVERLAY/kustomization.yaml" "collector values replacement"
require 'metrics/prometheus-crds' "$E2E_OVERLAY/otel-values.yaml" "Prometheus CRD metrics pipeline"
require 'exporters:[[:space:]]*\[otlphttp/victoriametrics\]' "$E2E_OVERLAY/otel-values.yaml" "local-only metrics exporter"
reject 'otel-gateway\.us-east-1\.example\.com' "$E2E_OVERLAY/otel-values.yaml" "external upstream dependency"

require 'cgroup2fs' "$CILIUM_SCRIPT" "cgroup v2 preflight"
require 'default-cgroupns-mode' "$CILIUM_SCRIPT" "private cgroup namespace guidance"
require 'oci://quay\.io/cilium/charts/cilium' "$CILIUM_SCRIPT" "Cilium OCI chart install"
require 'KubeProxyReplacement' "$CILIUM_SCRIPT" "kube-proxy replacement doctor check"
require 'kindnet' "$CILIUM_SCRIPT" "Kind default CNI baseline check"
require 'Hubble' "$CILIUM_SCRIPT" "Hubble doctor check"
require 'ServiceMonitor' "$CILIUM_SCRIPT" "ServiceMonitor doctor check"

require '^AQUA[[:space:]]*\?=' "$MAKEFILE" "aqua variable"
require '^DOCKER[[:space:]]*\?=' "$MAKEFILE" "Docker variable"
require '^KIND[[:space:]]*\?=.*AQUA.*kind' "$MAKEFILE" "aqua-managed kind"
require '^KUBECTL[[:space:]]*\?=.*AQUA.*kubectl' "$MAKEFILE" "aqua-managed kubectl"
require '^HELM[[:space:]]*\?=.*AQUA.*helm' "$MAKEFILE" "aqua-managed Helm"
require '^FLUX[[:space:]]*\?=.*AQUA.*flux' "$MAKEFILE" "aqua-managed Flux"
require '^CILIUM_VERSION[[:space:]]*\?=' "$MAKEFILE" "Cilium version variable"
require '^PROMETHEUS_OPERATOR_VERSION[[:space:]]*\?=' "$MAKEFILE" "Prometheus Operator version variable"
require '^tools-install:' "$MAKEFILE" "tool install target"
require '^tools-check:' "$MAKEFILE" "tool check target"
require '^e2e-kind-host-check:' "$MAKEFILE" "e2e host check target"
require '^e2e-kind-ensure:' "$MAKEFILE" "Kind ensure target"
require '^e2e-kind-cilium-install:' "$MAKEFILE" "Cilium install target"
require '^e2e-kind-flux-install:' "$MAKEFILE" "Flux install target"
require '^e2e-kind-check:' "$MAKEFILE" "Kind check target"
require '^e2e-kind-artifacts:' "$MAKEFILE" "artifact collection target"
