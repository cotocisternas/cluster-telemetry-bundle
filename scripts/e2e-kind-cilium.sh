#!/usr/bin/env sh
set -eu

command_name=${1:-doctor}

CLUSTER=${E2E_KIND_CLUSTER:-cluster-telemetry-bundle-e2e}
KUBE_CONTEXT=${E2E_KIND_CONTEXT:-kind-${CLUSTER}}
CILIUM_VERSION=${CILIUM_VERSION:-1.19.4}
CILIUM_VALUES=${CILIUM_VALUES:-test/e2e/cilium/values.yaml}
CILIUM_MONITORING_VALUES=${CILIUM_MONITORING_VALUES:-components/cilium-hubble-monitoring/values.yaml}
DOCKER=${DOCKER:-docker}
HELM=${HELM:-helm}
KUBECTL=${KUBECTL:-kubectl}

log() {
	printf '[e2e-kind-cilium] %s\n' "$*"
}

die() {
	printf '[e2e-kind-cilium] %s\n' "$*" >&2
	exit 1
}

require_command() {
	name=${1%% *}
	if ! command -v "$name" >/dev/null 2>&1; then
		die "missing required command: $name"
	fi
}

run_helm() {
	# HELM may contain arguments, matching the Makefile override style.
	# shellcheck disable=SC2086
	$HELM --kube-context "$KUBE_CONTEXT" "$@"
}

run_kubectl() {
	# KUBECTL may contain arguments, matching the Makefile aqua wrapper.
	# shellcheck disable=SC2086
	$KUBECTL --context "$KUBE_CONTEXT" "$@"
}

kernel_at_least_5_14() {
	version=$(uname -r | sed 's/[^0-9.].*$//')
	major=${version%%.*}
	rest=${version#*.}
	minor=${rest%%.*}
	[ "${major:-0}" -gt 5 ] || { [ "${major:-0}" -eq 5 ] && [ "${minor:-0}" -ge 14 ]; }
}

preflight_host() {
	require_command "$DOCKER"

	cgroup_type=$(stat -fc %T /sys/fs/cgroup)
	if [ "$cgroup_type" != "cgroup2fs" ]; then
		die "cgroup v2 is required for Cilium Socket LB on Kind; /sys/fs/cgroup is $cgroup_type"
	fi

	cgroup_version=$("$DOCKER" info --format '{{.CgroupVersion}}')
	if [ "$cgroup_version" != "2" ]; then
		die "Docker cgroup v2 is required, got $cgroup_version"
	fi

	security_options=$("$DOCKER" info --format '{{range .SecurityOptions}}{{println .}}{{end}}')
	if ! printf '%s\n' "$security_options" | grep -Fx 'name=cgroupns' >/dev/null 2>&1; then
		die "Docker must use private cgroup namespaces; set dockerd --default-cgroupns-mode=private"
	fi

	if ! kernel_at_least_5_14; then
		die "kernel 5.14+ is required unless cgroup v1 net_cls/net_prio are disabled"
	fi
}

kind_node_names() {
	"$DOCKER" ps \
		--filter "label=io.x-k8s.kind.cluster=$CLUSTER" \
		--format '{{.Names}}'
}

preflight_kind_nodes() {
	host_cgroup=$(ls -al /proc/self/ns/cgroup)
	nodes=$(kind_node_names)
	if [ -z "$nodes" ]; then
		die "no Kind nodes found for cluster $CLUSTER"
	fi

	for node in $nodes; do
		node_cgroup=$("$DOCKER" exec "$node" ls -al /proc/self/ns/cgroup)
		if [ "$node_cgroup" = "$host_cgroup" ]; then
			die "Kind node $node shares the host cgroup namespace; recreate with private cgroup namespaces"
		fi
	done
}

check_kind_cni_baseline() {
	require_command "$KUBECTL"
	if run_kubectl -n kube-system get daemonset kube-proxy >/dev/null 2>&1; then
		die "kube-proxy daemonset exists before Cilium install; recreate $CLUSTER with kubeProxyMode=none"
	fi
	if run_kubectl -n kube-system get daemonset kindnet >/dev/null 2>&1; then
		die "kindnet daemonset exists before Cilium install; recreate $CLUSTER with disableDefaultCNI=true"
	fi
}

control_plane_ip() {
	"$DOCKER" inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CLUSTER-control-plane"
}

install_cilium() {
	require_command "$HELM"
	require_command "$KUBECTL"
	preflight_host
	preflight_kind_nodes
	check_kind_cni_baseline
	[ -f "$CILIUM_VALUES" ] || die "Cilium Kind values not found: $CILIUM_VALUES"
	[ -f "$CILIUM_MONITORING_VALUES" ] || die "Cilium monitoring values not found: $CILIUM_MONITORING_VALUES"

	api_host=$(control_plane_ip)
	if [ -z "$api_host" ]; then
		die "could not discover $CLUSTER-control-plane IP"
	fi

	log "installing Cilium $CILIUM_VERSION with kube-proxy replacement and Hubble metrics"
	run_helm upgrade --install cilium oci://quay.io/cilium/charts/cilium \
		--namespace kube-system \
		--version "$CILIUM_VERSION" \
		--values "$CILIUM_VALUES" \
		--values "$CILIUM_MONITORING_VALUES" \
		--set k8sServiceHost="$api_host" \
		--set k8sServicePort=6443
}

wait_cilium() {
	require_command "$KUBECTL"
	run_kubectl -n kube-system rollout status daemonset/cilium --timeout=180s
	run_kubectl -n kube-system rollout status deployment/cilium-operator --timeout=180s
	run_kubectl -n kube-system rollout status deployment/hubble-relay --timeout=180s
	run_kubectl -n kube-system rollout status deployment/coredns --timeout=180s
}

cilium_status() {
	run_kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
}

check_cilium_status() {
	status=$(cilium_status)
	printf '%s\n' "$status" | grep -Eq 'KubeProxyReplacement:[[:space:]]+True' ||
		die "Cilium did not report KubeProxyReplacement: True"
	printf '%s\n' "$status" | grep -Eq 'Hubble:[[:space:]]+Ok' ||
		die "Cilium did not report Hubble: Ok"
	if run_kubectl -n kube-system get daemonset kube-proxy >/dev/null 2>&1; then
		die "kube-proxy daemonset exists; e2e Kind must use Cilium replacement only"
	fi
	if run_kubectl -n kube-system get daemonset kindnet >/dev/null 2>&1; then
		die "kindnet daemonset exists; recreate the Kind cluster with disableDefaultCNI=true"
	fi
}

check_cilium_service_monitors() {
	run_kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 ||
		die "ServiceMonitor CRD is required before Cilium monitoring checks"
	count=$(run_kubectl get servicemonitor -A -l telemetry.example.com/scrape=true --no-headers 2>/dev/null | wc -l | tr -d ' ')
	if [ "${count:-0}" -lt 4 ]; then
		die "expected Cilium/Hubble ServiceMonitors labeled telemetry.example.com/scrape=true, got $count"
	fi
	run_kubectl -n kube-system get servicemonitor -l telemetry.example.com/scrape=true >/dev/null
}

doctor() {
	preflight_host
	preflight_kind_nodes
	wait_cilium
	check_cilium_status
	check_cilium_service_monitors
	log "Cilium Kind checks passed"
}

case "$command_name" in
	preflight)
		preflight_host
		;;
	baseline)
		check_kind_cni_baseline
		;;
	install)
		install_cilium
		;;
	wait)
		wait_cilium
		;;
	doctor)
		doctor
		;;
	*)
		die "unknown command: $command_name"
		;;
esac
