#!/usr/bin/env sh
set -eu

KUBECTL=${KUBECTL:-kubectl}

fail() {
	echo "rendered invariant check failed: $1" >&2
	exit 1
}

render() {
	# KUBECTL may intentionally contain spaces, for example "aqua exec -- kubectl".
	# shellcheck disable=SC2086
	$KUBECTL kustomize "$1"
}

if grep -RInE 'version:[[:space:]]*".*\.x"' base >/tmp/cluster-telemetry-bundle-chart-wildcards.txt; then
	cat /tmp/cluster-telemetry-bundle-chart-wildcards.txt >&2
	fail "HelmRelease chart versions must be exact pins"
fi

if grep -Eq '^[[:space:]]*replicaCount:[[:space:]]*[2-9][0-9]*[[:space:]]*$' base/otel-collector/values.yaml \
	&& grep -q 'tail_sampling:' base/otel-collector/values.yaml \
	&& ! grep -RIEq 'loadbalancing:|routing_key:[[:space:]]*traceID' base/otel-collector; then
	fail "tail_sampling must not run with multiple collector replicas unless traces are routed by trace ID"
fi

for values_file in \
	examples/cluster-us-east-1/otel-values.yaml \
	examples/cluster-us-east-1-prometheus-crds/otel-values.yaml \
	test/e2e/overlays/kind-cilium/otel-values.yaml; do
	if ! grep -Eq 'name:[[:space:]]*CLUSTER' "$values_file"; then
		fail "$values_file does not set the required CLUSTER value"
	fi
	if grep -Eq 'UNSET-OVERRIDE-IN-OVERLAY|base-cluster' "$values_file"; then
		fail "$values_file still uses a placeholder CLUSTER value"
	fi
done

for entrypoint in \
	examples/cluster-us-east-1 \
	examples/cluster-us-east-1-prometheus-crds \
	examples/cluster-us-east-1-monitoring-bundle \
	test/e2e/overlays/kind-cilium; do
	if render "$entrypoint" | grep -q 'base-cluster'; then
		fail "$entrypoint still renders the old base-cluster placeholder"
	fi
done
