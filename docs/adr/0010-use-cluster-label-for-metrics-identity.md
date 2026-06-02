# Use cluster label for metrics identity

Accepted.

Cluster Telemetry Bundle uses `cluster` as the Prometheus/Grafana-facing metrics
label for Monitored Cluster identity. The value is a required per-overlay GitOps
value rather than a value guessed at runtime. For OpenTelemetry resource
identity, the bundle follows Kubernetes semantic conventions such as
`k8s.cluster.name` and, when available, `k8s.cluster.uid`.

## Consequences

Local metrics queries, canary validation, KEDA examples, and dashboards should
filter by `cluster`. Collector configuration may preserve or emit
`k8s.cluster.name` and `k8s.cluster.uid` for OTLP consumers, but should not
invent `cluster_id` as the canonical query label.

Configuration and examples should replace tenant-oriented names such as
`TENANT_ID` and `tenant_id` when they are being used only to identify the
cluster. The configured cluster name should become the Prometheus-compatible
`cluster` label for metrics and should also be available as Kubernetes cluster
resource identity for OTLP consumers.

Cluster overlays must set the `cluster` value explicitly. Automatic discovery
may populate supporting attributes such as `k8s.cluster.uid`, but it should not
replace the operator-chosen `cluster` label used in Prometheus and Grafana
queries.
