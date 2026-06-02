# Expose metrics without owning rollout rules

Accepted.

Cluster Telemetry Bundle provides the local metrics substrate used by canary validation and
autoscaling consumers, but it does not install workload-specific canary or KEDA
rules by default. Those rules belong to the workload or platform layer that owns
the rollout and scaling policy.

```text
cluster-telemetry-bundle:
  OTel Collector -> VictoriaMetrics -> Prometheus-compatible metrics

outside this repo:
  metrics queries -> canary decisions
  metrics queries -> KEDA scaling decisions
```

## Consequences

The bundle should expose stable metrics and labels for consumers. It may include
examples or templates, but default installation should not include generic
rollout thresholds or scaling decisions.
