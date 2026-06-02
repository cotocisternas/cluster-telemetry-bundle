# Per-Cluster Overlay With Prometheus CRD Scraping

This overlay extends `examples/cluster-us-east-1` with OpenTelemetry Target
Allocator support for Prometheus Operator scrape CRDs.

Use this only in clusters where the Prometheus Operator CRDs are installed:

- `ServiceMonitor`
- `PodMonitor`

`Probe` is also a Prometheus Operator CRD, but it is for blackbox-style probing
through a prober exporter. It is not part of this gateway's default application
metric scraping path.

## Runtime Shape

```text
ServiceMonitor / PodMonitor
        |
        | selected by label:
        | telemetry.example.com/scrape=true
        v
OpenTelemetry Target Allocator
        |
        | HTTP service discovery per collector pod
        v
OTel Collector prometheus receiver
        |
        +-- local metrics --> VictoriaMetrics
        |
        +-- upstream -----> OTLP/gRPC endpoint
```

## Required Label

The Target Allocator only watches `ServiceMonitor` and `PodMonitor` resources
with this metadata label:

```yaml
metadata:
  labels:
    telemetry.example.com/scrape: "true"
```

This keeps the gateway from accidentally scraping every Prometheus Operator
target in the cluster.

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

## Validate

```bash
kubectl kustomize examples/cluster-us-east-1-prometheus-crds
```

Before applying this overlay, verify that the cluster has the Prometheus
Operator CRDs installed:

```bash
kubectl get crd servicemonitors.monitoring.coreos.com
kubectl get crd podmonitors.monitoring.coreos.com
```
