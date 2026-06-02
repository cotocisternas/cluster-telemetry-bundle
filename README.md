# cluster-telemetry-bundle

cluster-telemetry-bundle is a Flux GitOps module for deploying a cluster monitoring
bundle with a gateway-first telemetry data plane.

It receives telemetry from workloads and node collectors, keeps a short-lived
local metrics cache for deployment validation and autoscaling signals, and
forwards metrics, logs, and traces to the next upstream OpenTelemetry endpoint.

It installs and wires:

- OpenTelemetry Collector for OTLP ingestion, enrichment, sampling, local
  metrics export, and upstream forwarding
- VictoriaMetrics as the ephemeral local metrics cache exposed through
  Prometheus-compatible APIs
- Fluent Bit for node and container log collection into the collector
- Optional metric source profiles for Prometheus Operator CRDs, Kubernetes
  object state, node host metrics, and Cilium/Hubble telemetry

## Architecture At A Glance

```text
                  Kubernetes cluster

  +-------------+      OTLP/gRPC or OTLP/HTTP
  | Workloads   |-------------------------------+
  +-------------+                               |
                                                v
  +-------------+      OTLP/HTTP        +---------------------+
  | Fluent Bit  |---------------------->| OTel Collector      |
  | node logs   |                       | - enrich/scrub      |
  +-------------+                       | - sample traces     |
                                        | - bounded retry     |
                                        +----------+----------+
                                                   |
                     metrics only                  | metrics/logs/traces
                         v                         v
              +--------------------+      +---------------------+
              | VictoriaMetrics    |      | Upstream Telemetry  |
              | local cache        |      | Endpoint            |
              +---------+----------+      +---------------------+
                        ^
                        |
             +----------+-----------+
             | Canary and KEDA      |
             | rules outside repo   |
             +----------------------+
```

More detail lives in `docs/architecture.md`. The documentation index is
`docs/README.md`.

## Product Shape

The intent is closer to `kube-prometheus-stack` than to a standalone collector
chart: one Flux-friendly package for the monitoring concerns a cluster
needs. The difference is the data plane and defaults.

```text
kube-prometheus-stack shape:
  Prometheus Operator + Prometheus + Alertmanager + Grafana
  + kube-state-metrics + node-exporter + rules + dashboards

cluster-telemetry-bundle shape:
  OTel Collector + VictoriaMetrics local cache + Fluent Bit
  + metric source profiles + upstream OTLP forwarding
  + Flux valuesFrom overlays
```

Profiles let the bundle grow without forcing every cluster to install every
monitoring component:

```text
core:
  collector, local cache, log collection, upstream forwarding

prometheus-crds:
  ServiceMonitor and PodMonitor discovery through Target Allocator

cluster-state:
  kube-state-metrics for Kubernetes object state, exposed through ServiceMonitor

node-metrics:
  node-exporter for host metrics when the bundle owns that source

cilium-hubble:
  Cilium, Cilium Operator, Hubble, and Hubble Relay metrics when Cilium is platform-owned

presentation:
  dashboards and rules, owned as examples/templates before becoming defaults
```

See `docs/monitoring-bundle-profiles.md` for the profile model.

## Repository Layout

```text
/
|-- base/                     # Core Flux/Kustomize base
|   |-- components/           # Optional Kustomize components
|   |   |-- cilium-hubble-monitoring/ # Cilium/Hubble values profile
|   |   |-- kube-state-metrics/       # Kubernetes object state metrics
|   |   |-- node-exporter/            # Node host metrics
|   |   `-- prometheus-crd-scrape/    # ServiceMonitor/PodMonitor scraping
|   |-- fluent-bit/            # Fluent Bit HelmRepository, HelmRelease, values
|   |-- otel-collector/        # OTel HelmRepository, HelmRelease, values
|   |-- shared/                # Namespace and shared resources
|   `-- victoria-metrics/      # VictoriaMetrics HelmRepository, HelmRelease, values
|-- docs/                     # Architecture notes, operator docs, and ADRs
|-- test/e2e/                 # Kind/Cilium e2e environment
`-- examples/
    |-- cluster-us-east-1/                     # Example per-cluster overlay
    |-- cluster-us-east-1-prometheus-crds/     # Overlay with ServiceMonitor/PodMonitor scraping
    |-- cluster-us-east-1-monitoring-bundle/   # Overlay with source profiles
    `-- flux/                                  # Remote GitRepository/Kustomization examples
```

## Signal Flow

- Workloads send OTLP/gRPC to port `4317` or OTLP/HTTP to port `4318` on the
  OpenTelemetry Collector service.
- Fluent Bit tails container logs and forwards them to the collector with
  OTLP/HTTP.
- Metrics are written to local VictoriaMetrics for canary validation, KEDA
  rules, and other cluster-local checks.
- Metrics, logs, and traces are forwarded upstream through the collector
  `otlp/upstream` exporter using OTLP/gRPC by default.
- Local storage is intentionally metrics-only and ephemeral. Logs and traces
  are processed, scrubbed, sampled where applicable, and forwarded without local
  query storage.
- The collector keeps error and slow traces, plus a small probabilistic baseline,
  before forwarding traces upstream.

```text
Signal        Local cache                 Upstream forwarding
------------  --------------------------  ------------------------------
Metrics       VictoriaMetrics, 24h        OTLP/gRPC through collector
Logs          None                        OTLP/gRPC through collector
Traces        None                        OTLP/gRPC through collector
Log metrics   VictoriaMetrics, 24h        OTLP/gRPC through collector
```

## Pod Security

The `telemetry` namespace enforces Kubernetes Pod Security `privileged` because
the base bundle includes host-level collectors. Fluent Bit tails node container
logs through host paths, and the optional node-exporter profile also uses host
namespaces and host paths. Clusters that need stricter separation should deploy
host collectors in a dedicated privileged namespace and keep pure gateway
components in a restricted namespace.

## Prometheus Operator CRDs

Cluster Telemetry Bundle supports Prometheus Operator metric scrape CRDs in two ways:

```text
self-monitoring:
  Prometheus Operator -> ServiceMonitor -> gateway component metrics

application metric scraping:
  ServiceMonitor / PodMonitor -> Target Allocator -> OTel Collector
```

The base install does not require Prometheus Operator CRDs. Collector and
VictoriaMetrics values include disabled `ServiceMonitor` hooks for clusters
that want an existing Prometheus stack to scrape the gateway's own metrics.

Application metric scraping is opt-in through
`examples/cluster-us-east-1-prometheus-crds`. That overlay deploys the
OpenTelemetry Target Allocator and configures a dedicated collector
`metrics/prometheus-crds` pipeline. It selects only `ServiceMonitor` and
`PodMonitor` resources labeled `telemetry.example.com/scrape=true`.

The `examples/cluster-us-east-1-monitoring-bundle` overlay extends that path
with kube-state-metrics and node-exporter profiles. Those charts publish
ServiceMonitors with the same selector label, so their metrics flow through the
Target Allocator, OTel Collector, VictoriaMetrics local cache, and upstream OTLP
forwarding path.

See `docs/prometheus-operator-crds.md` for details.

## Cilium And Hubble Metrics

Cluster Telemetry Bundle does not own the cluster CNI. When a cluster uses Cilium, the
optional `base/components/cilium-hubble-monitoring` profile provides a Cilium
Helm values fragment that enables Cilium, Cilium Operator, Hubble, and Hubble
Relay metrics and labels their ServiceMonitors for Target Allocator discovery.

```text
Cilium / Hubble ServiceMonitors
        |
        | telemetry.example.com/scrape=true
        v
Target Allocator -> OTel Collector -> VictoriaMetrics + upstream OTLP
```

See `docs/cilium-hubble-monitoring.md` for the production integration model.

## Design

The repo uses Kustomize as the composition layer and Flux HelmRelease as the
chart installation layer. It does not package the stack as an umbrella Helm
chart.

Base chart values live in plain values files:

- `base/fluent-bit/values.yaml`
- `base/otel-collector/values.yaml`
- `base/victoria-metrics/values.yaml`

Each base `kustomization.yaml` turns its values file into a watched ConfigMap.
Each HelmRelease reads values from that ConfigMap and then from an optional
cluster override ConfigMap.

For example, the OTel HelmRelease reads:

```yaml
valuesFrom:
  - kind: ConfigMap
    name: opentelemetry-collector-values
    valuesKey: values.yaml
  - kind: ConfigMap
    name: opentelemetry-collector-cluster-values
    valuesKey: values.yaml
    optional: true
```

Flux merges `valuesFrom` entries in order, so cluster values override base
values. Inline `spec.values` should stay empty for these HelmReleases because
inline values have higher priority than `valuesFrom`.

```text
base/<component>/values.yaml
        |
        v
base generated ConfigMap
        |
        v
HelmRelease valuesFrom[0]
        |
        +---- optional cluster ConfigMap
                         |
                         v
              HelmRelease valuesFrom[1]
                         |
                         v
                 rendered Helm values
```

See `docs/adr/0001-use-flux-valuesfrom-for-chart-values.md` for the values
composition decision.

## Identity

Cluster overlays set the Prometheus/Grafana-facing cluster identity explicitly
through the `CLUSTER` environment value in the OTel values override. The
collector emits it as the local metrics label `cluster` and as the OTel resource
attribute `k8s.cluster.name`.

Use `cluster` in local metrics queries, canary validation checks, KEDA rules,
and dashboards. Do not introduce `tenant_id`, `site_id`, or `cluster_id` for
this query identity.

## Upstream Forwarding

The base collector values define `UPSTREAM_OTLP_GRPC_ENDPOINT` as a placeholder.
Every real cluster overlay should override it with the next upstream OTLP/gRPC
endpoint in `host:port` form.

The upstream exporter uses bounded retry and queueing. If the upstream remains
unavailable past the retry window or queue capacity, telemetry can be dropped;
operators should monitor collector health and exporter failure metrics for that
loss signal.

Upstream authentication, private CA bundles, or plaintext compatibility are
overlay-specific concerns. The base manifests do not ship default credential
Secrets. See `docs/secrets.md` for the override pattern.

## Prerequisites

- Kubernetes cluster
- Flux installed with source-controller, kustomize-controller, and
  helm-controller
- `kubectl` with Kustomize support for local rendering
- An upstream OTLP/gRPC endpoint for real deployments

## Render Locally

Render the reusable base:

```bash
kubectl kustomize base
```

Render the sample cluster overlay:

```bash
kubectl kustomize examples/cluster-us-east-1
```

Render the Prometheus CRD scraping overlay:

```bash
kubectl kustomize examples/cluster-us-east-1-prometheus-crds
```

Render the full monitoring bundle overlay with kube-state-metrics and
node-exporter profiles:

```bash
kubectl kustomize examples/cluster-us-east-1-monitoring-bundle
```

Render the Kind/Cilium e2e overlay:

```bash
kubectl kustomize test/e2e/overlays/kind-cilium
```

## Kind E2E

The local e2e environment is production-like: Kind runs without the default CNI
or kube-proxy, Cilium provides the datapath, Hubble metrics are enabled, Flux
reconciles the bundle, and ServiceMonitor discovery feeds the collector.

```bash
make e2e-kind-up
make e2e-kind-artifacts
make e2e-kind-delete
```

The e2e path requires `aqua`, Docker, and network access for the Cilium OCI
chart and Prometheus Operator CRDs. The Kubernetes CLIs are pinned in
`aqua.yaml`:

```bash
make tools-install
make tools-check
```

See `docs/kind-e2e.md` for the full flow.

## Deploy With Flux

A platform GitOps repository should point a Flux Kustomization at the desired
remote overlay path. The examples under `examples/flux` include both the
`GitRepository` source and the Flux `Kustomization`:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: cluster-telemetry-bundle
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/cotocisternas/cluster-telemetry-bundle.git
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-telemetry-bundle
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: cluster-telemetry-bundle
  path: ./examples/cluster-us-east-1
  prune: true
  interval: 10m
```

Optional profiles can be added through Flux/Kustomize components:

```yaml
spec:
  path: ./examples/cluster-us-east-1
  components:
    - ../../base/components/prometheus-crd-scrape
    - ../../base/components/kube-state-metrics
    - ../../base/components/node-exporter
```

## Create A Cluster Overlay

Copy the example overlay:

```bash
cp -r examples/cluster-us-east-1 examples/cluster-eu-west-1
```

Then edit the copied overlay:

- Set `CLUSTER` in `otel-values.yaml` to the cluster label used in local metrics
  queries.
- Set `UPSTREAM_OTLP_GRPC_ENDPOINT` to the next upstream OTLP/gRPC endpoint.
- Tune the OTel sampling percentage for the cluster traffic profile.
- Add overlay-only secret, TLS, or header configuration if the upstream requires
  authentication or a custom trust bundle.

Canary and KEDA rules live outside this repository. They should consume the
Prometheus-compatible VictoriaMetrics endpoint exposed by this module and
filter local metrics with the `cluster` label.

## Boundaries

```text
Owned here:
  +--------------------------------------------------------------+
  | telemetry namespace, collector, local metrics cache,          |
  | node log collection, base values, and overlay extension points |
  +--------------------------------------------------------------+

Owned outside this repo:
  +--------------------------------------------------------------+
  | workload instrumentation, upstream telemetry backend,         |
  | canary policies, KEDA ScaledObjects, dashboards, and alerts    |
  +--------------------------------------------------------------+
```

## Validation

Before committing changes:

```bash
kubectl kustomize base
kubectl kustomize examples/cluster-us-east-1
kubectl kustomize examples/cluster-us-east-1-prometheus-crds
kubectl kustomize examples/cluster-us-east-1-monitoring-bundle
kubectl kustomize test/e2e/overlays/kind-cilium
make e2e-kind-static-check
git diff --check
```

For cluster overlays, inspect the rendered values ConfigMaps and HelmRelease
references:

```bash
kubectl kustomize examples/cluster-us-east-1 | grep -A30 'name: opentelemetry-collector-cluster-values'
kubectl kustomize examples/cluster-us-east-1 | grep 'valuesFrom'
```
