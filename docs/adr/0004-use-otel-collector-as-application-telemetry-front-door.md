# Use OTel Collector as application telemetry front door

Accepted.

Cluster Telemetry Bundle uses OTel Collector as the front door for application telemetry.
Applications, SDKs, sidecars, and instrumented services send OTLP telemetry to
the collector, while Fluent Bit is scoped to Kubernetes node and container log
collection.

## Consequences

OTel Collector owns enrichment, routing, sampling, local metrics fanout, and
upstream forwarding. Fluent Bit should optimize log collection and forwarding
into the collector, not act as the general receiver for metrics, traces, and
application OTLP traffic.
