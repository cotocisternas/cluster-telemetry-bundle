# Prometheus Operator CRD Support

Cluster Telemetry Bundle can support Prometheus-style application metrics through
Prometheus Operator scrape CRDs.

The common CRDs are:

- `ServiceMonitor`: selects Services and named Service ports to scrape.
- `PodMonitor`: selects Pods and named container ports to scrape.
- `Probe`: describes blackbox-style probing through a prober exporter.

For application metrics, use `ServiceMonitor` first. Use `PodMonitor` when the
workload does not have a stable Service. `Probe` is not part of the default
application metric collection path.

## Collection Model

```text
ServiceMonitor / PodMonitor
        |
        v
OpenTelemetry Target Allocator
        |
        v
OTel Collector prometheus receiver
        |
        +-- VictoriaMetrics local cache
        |
        +-- upstream OTLP/gRPC forwarding
```

The Target Allocator watches selected `ServiceMonitor` and `PodMonitor`
resources and exposes per-collector HTTP service discovery. The collector's
Prometheus receiver reads those target assignments, scrapes the targets, and
sends the resulting metrics through the same local and upstream metric paths as
OTLP metrics.

## Opt-In Overlay

The reusable base does not render Prometheus Operator CRD-dependent resources by
default. To enable CRD scraping for a cluster, use the opt-in example overlay:

```bash
kubectl kustomize examples/cluster-us-east-1-prometheus-crds
```

That overlay adds:

- `components/prometheus-crd-scrape`: the OpenTelemetry Target Allocator
  HelmRelease and collector profile values.
- A collector values override with a `prometheus` receiver using the Target
  Allocator endpoint.
- An optional `opentelemetry-target-allocator-cluster-values` hook for
  cluster-specific Target Allocator Helm values, such as custom
  `ServiceMonitor` and `PodMonitor` selector labels.
- A dedicated `metrics/prometheus-crds` pipeline that does not run the generic
  OTLP metric scrubber, so Prometheus metric labels are preserved.

For a fuller monitoring bundle, use:

```bash
kubectl kustomize examples/cluster-us-east-1-monitoring-bundle
```

That overlay adds kube-state-metrics and node-exporter profiles. Their charts
create ServiceMonitors with the same selector label, so cluster object state and
node host metrics follow the Target Allocator path instead of bypassing the
collector.

## Selector Contract

Only CRDs with this metadata label are selected:

```yaml
metadata:
  labels:
    telemetry.example.com/scrape: "true"
```

This is intentionally narrower than selecting every CRD in the cluster.
Workload teams opt into collection by adding the label to their
`ServiceMonitor` or `PodMonitor`.

To change this selector for a cluster, create
`opentelemetry-target-allocator-cluster-values` in the `telemetry` namespace and
override `targetAllocator.config.prometheus_cr.service_monitor_selector` and
`targetAllocator.config.prometheus_cr.pod_monitor_selector`. The Flux copy-paste
example in `examples/flux/prometheus-crds` demonstrates that pattern.

## Example ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: example-workload
  namespace: example-app
  labels:
    telemetry.example.com/scrape: "true"
spec:
  namespaceSelector:
    matchNames:
      - example-app
  selector:
    matchLabels:
      app.kubernetes.io/name: example-workload
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

## Self-Monitoring

The base collector and VictoriaMetrics values include disabled
`ServiceMonitor` hooks for clusters that already run Prometheus Operator and
want Prometheus to scrape the gateway's own health metrics:

```yaml
serviceMonitor:
  enabled: true
  extraLabels:
    release: kube-prometheus-stack
```

For the collector, the chart also supports `podMonitor.enabled` if scraping pods
directly is preferred.

## Requirements

Prometheus Operator CRDs must exist before applying the opt-in overlay:

```bash
kubectl get crd servicemonitors.monitoring.coreos.com
kubectl get crd podmonitors.monitoring.coreos.com
```

The base install does not require these CRDs.
