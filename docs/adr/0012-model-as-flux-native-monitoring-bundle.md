# Model as Flux-native monitoring bundle

Accepted.

Cluster Telemetry Bundle should not be a narrow collector gateway. It should be a
Flux-native monitoring bundle for clusters, similar in deployment intent
to kube-prometheus-stack: a single package for monitoring concerns.

```text
kube-prometheus-stack:
  Prometheus Operator + Prometheus + Alertmanager + Grafana
  + kube-state-metrics + node-exporter + dashboards + rules

Cluster Telemetry Bundle:
  OTel Collector + VictoriaMetrics + Fluent Bit
  + metric source profiles + upstream OTLP forwarding
  + Flux valuesFrom overlays
```

## Consequences

The core data plane remains gateway-first: telemetry is collected, locally
cached for validation, and forwarded upstream over OTLP/gRPC. The product scope
can include kube-state-metrics, node-exporter, dashboards, and rules, but these
enter as profiles so clusters can avoid duplicate agents and control cost.

The initial source profiles are kube-state-metrics for Kubernetes object state
and prometheus-node-exporter for node host metrics. They remain opt-in because
some platform teams already provide those sources and duplicate installation can
double scrape volume or create conflicting ownership.

The bundle should remain optimized for Flux deployments: values live in files,
HelmReleases consume generated ConfigMaps with `valuesFrom`, and examples show
profile composition through overlays.

Because the base bundle owns Fluent Bit host log collection, its namespace cannot
use Pod Security `baseline` enforcement. The shared namespace uses `privileged`
enforcement, with baseline warn/audit labels to keep host-level requirements
visible during admission.
