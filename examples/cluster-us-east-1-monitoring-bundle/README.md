# Per-Cluster Monitoring Bundle Overlay

This overlay composes the gateway, Prometheus CRD scraping, kube-state-metrics,
and node-exporter profiles. It is the closest example to the
`kube-prometheus-stack` deployment shape while keeping Cluster Telemetry Bundle's
OpenTelemetry and VictoriaMetrics data plane.

Use this when the cluster should own its basic monitoring sources through
this bundle. Do not use it if the platform already provides kube-state-metrics
or node-exporter and you only need to consume those existing metrics.

## Runtime Shape

```text
kube-state-metrics ServiceMonitor ----+
                                      |
node-exporter ServiceMonitor --------+
                                      |
workload ServiceMonitor / PodMonitor-+--> Target Allocator
                                               |
                                               v
                                        OTel Collector
                                               |
                         +---------------------+---------------------+
                         |                                           |
                         v                                           v
                 VictoriaMetrics                              upstream OTLP/gRPC
                 local metrics cache
```

## Included Profiles

```text
core:
  OTel Collector, VictoriaMetrics, Fluent Bit, and upstream forwarding

prometheus-crds:
  Target Allocator discovery for selected ServiceMonitor and PodMonitor objects

cluster-state:
  kube-state-metrics with a ServiceMonitor labeled for Target Allocator

node-metrics:
  prometheus-node-exporter with a ServiceMonitor labeled for Target Allocator
```

Both metric-source charts keep their own cluster override hooks:

```text
kube-state-metrics-cluster-values
node-exporter-cluster-values
```

Create those ConfigMaps in a cluster overlay only when resource limits,
tolerations, collector lists, or scrape settings need cluster-specific tuning.

The metric-source HelmReleases depend on `opentelemetry-target-allocator`.
Deploy them with the Prometheus CRD scraping profile so their ServiceMonitors
are discovered and scraped through the collector path.

## Requirements

Prometheus Operator CRDs must exist before applying this overlay:

```bash
kubectl get crd servicemonitors.monitoring.coreos.com
kubectl get crd podmonitors.monitoring.coreos.com
```

The profile ServiceMonitors use this selector label:

```yaml
metadata:
  labels:
    telemetry.example.com/scrape: "true"
```

## Validate

```bash
kubectl kustomize examples/cluster-us-east-1-monitoring-bundle
```
