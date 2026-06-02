# Kind E2E Environment

The local e2e environment validates the full monitoring bundle in a Cilium-backed
Kind cluster.

It follows a production-like local validation shape:

```text
Kind cluster
  disableDefaultCNI: true
  kubeProxyMode: none
        |
        v
Cilium kube-proxy replacement + Hubble metrics
        |
        v
Flux install
        |
        v
Cluster Telemetry Bundle full bundle overlay
        |
        v
ServiceMonitor -> Target Allocator -> OTel Collector -> VictoriaMetrics
```

## Requirements

- `aqua`
- Docker with cgroup v2 and private cgroup namespaces
- Linux kernel 5.14 or newer
- Network access for `aqua install`
- Network access to the Cilium OCI chart

The repo pins its e2e CLIs in `aqua.yaml`:

```text
kind v0.31.0
kubectl v1.36.1
helm v3.21.0
flux v2.8.8
```

## Commands

```bash
make tools-install
make tools-check
make e2e-kind-up
make e2e-kind-check
make e2e-kind-artifacts
make e2e-kind-delete
```

`make e2e-kind-up` performs these steps:

```text
1. Create or reuse the Kind cluster.
2. Install vendored ServiceMonitor and PodMonitor CRDs.
3. Install Cilium 1.19.4 with kube-proxy replacement and Hubble metrics.
4. Install Flux controllers.
5. Apply test/e2e/overlays/kind-cilium.
6. Wait for Cilium and the Cluster Telemetry Bundle HelmReleases.
7. Verify labeled ServiceMonitors exist for Target Allocator discovery.
```

The e2e overlay uses the base `telemetry` namespace. That namespace enforces
Pod Security `privileged` because Fluent Bit and node-exporter need host paths
and host-level access.

## Files

```text
Makefile
aqua.yaml
scripts/e2e-kind-cilium.sh
scripts/check-e2e-kind.sh
scripts/collect-kind-artifacts.sh
test/e2e/kind/cluster-cilium.yaml
test/e2e/cilium/values.yaml
test/e2e/prometheus-operator-crds/
test/e2e/overlays/kind-cilium/
components/cilium-hubble-monitoring/values.yaml
```

## Artifact Collection

```bash
make e2e-kind-artifacts
```

The artifact collector writes cluster state, Flux objects, ServiceMonitor
objects, events, pod descriptions, and logs under `artifacts/kind` by default.

## Boundary

The e2e environment installs Cilium because the test cluster needs a CNI. The
production bundle does not install or own Cilium. Production clusters should use
`components/cilium-hubble-monitoring/values.yaml` only as a monitoring values profile
for an existing platform-owned Cilium HelmRelease.
