# Keep local validation cache metrics-only

Accepted.

Cluster Telemetry Bundle stores metrics locally for canary validation and autoscaling
signals, but forwards logs and traces without local storage. This keeps the
Cluster Telemetry Gateway from becoming a local observability backend while still
preserving the short-lived signals needed for rollout and scaling automation.

## Consequences

The local storage component should be optimized for queryable metrics and does
not need durable persistence. Logs and traces remain part of the telemetry
flow, but their durable storage and investigation experience belong upstream.
