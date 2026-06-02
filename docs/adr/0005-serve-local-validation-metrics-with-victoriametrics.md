# Serve local validation metrics with VictoriaMetrics

Accepted.

Cluster Telemetry Bundle uses VictoriaMetrics as the Local Validation Cache for short-lived
metrics needed by canary validation and autoscaling signals. The cache exposes
Prometheus-compatible query/read APIs for local consumers such as KEDA and
rollout validation tooling.

```text
OTel Collector --metrics--> VictoriaMetrics local cache
                                  |
                                  v
                         canary and KEDA consumers
```

## Consequences

VictoriaMetrics should use ephemeral storage by default. The local cache is not
a durable source of truth, and the gateway does not need local dashboards as a
first-class product surface.
