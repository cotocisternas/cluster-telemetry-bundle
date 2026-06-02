# Support Prometheus Operator CRDs with Target Allocator

Accepted.

Cluster Telemetry Bundle supports Prometheus Operator `ServiceMonitor` and `PodMonitor`
resources through the OpenTelemetry Target Allocator. The Target Allocator is
optional and is not part of the default base install.

```text
ServiceMonitor / PodMonitor
        |
        v
Target Allocator
        |
        v
OTel Collector prometheus receiver
        |
        +-- VictoriaMetrics local cache
        |
        +-- upstream OTLP/gRPC
```

## Consequences

Prometheus CRD scraping is opt-in because it adds CRD dependencies, RBAC, and a
new discovery control plane. The selector contract must be narrow by default:
Cluster Telemetry Bundle only selects `ServiceMonitor` and `PodMonitor` resources labeled
`telemetry.example.com/scrape=true`.

The collector uses a separate `metrics/prometheus-crds` pipeline so Prometheus
metric labels are preserved. Workload teams still own metric cardinality and
scrape endpoint correctness through their `ServiceMonitor` or `PodMonitor`
definitions.
