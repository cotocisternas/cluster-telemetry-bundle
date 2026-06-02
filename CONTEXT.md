# Cluster Telemetry Bundle

Cluster Telemetry Bundle is a Flux-native monitoring bundle context for
Kubernetes clusters. It packages monitoring concerns as one deployable unit while keeping
telemetry flowing upstream and preserving enough short-lived local signal to
validate deployments and drive operational automation.

## Language

**Cluster Telemetry Gateway**:
A per-cluster telemetry gateway that receives cluster telemetry, keeps a
short-lived local validation cache, and forwards telemetry to the next upstream
telemetry endpoint.
_Avoid_: Local observability backend

**Monitoring Bundle**:
A single deployable package for cluster monitoring concerns. It includes the
Cluster Telemetry Gateway, the Local Validation Cache, and optional metric source
profiles. It is closer in shape to kube-prometheus-stack than to a single
collector chart, but uses a gateway-first data plane and Flux-native
composition.
_Avoid_: One-off collector install, dashboard-only stack

**Metric Source Profile**:
An optional component set that adds a class of metrics to the bundle, such as
Kubernetes object state, node host metrics, or Prometheus Operator scrape CRDs.
Profiles feed the same local cache and upstream forwarding paths.
_Avoid_: Separate monitoring stack, unrelated addon

**Monitored Cluster**:
A Kubernetes cluster that runs the gateway and emits telemetry for
local validation and upstream aggregation.
_Avoid_: Edge site, tenant cluster

**Cluster Label**:
The Prometheus/Grafana-facing label that identifies the Monitored Cluster in local
metrics queries. Cluster Telemetry Bundle uses `cluster` for this label so canary
validation, autoscaling, and dashboards follow common Kubernetes monitoring
conventions. The value is explicitly set by each cluster overlay.
_Avoid_: tenant_id, site_id, cluster_id

**Kubernetes Cluster Resource Identity**:
The OpenTelemetry resource identity for the Monitored Cluster. Cluster Telemetry Bundle should
preserve Kubernetes semantic attributes such as `k8s.cluster.name`, and may use
`k8s.cluster.uid` when a stable UID is needed.
_Avoid_: Custom OTel-only cluster identity names

**Upstream Telemetry Endpoint**:
The next telemetry hop that receives forwarded telemetry from a Cluster Telemetry
Gateway. It may be regional, central, or another aggregation tier.
_Avoid_: Central store, backend, sink

**Local Validation Cache**:
Short-lived local metrics storage used for deployment validation and
operational automation when upstream visibility is delayed or unavailable. It
does not store logs or traces locally.
_Avoid_: Persistent observability store, archive, durable source of truth

**Bounded Forwarding Buffer**:
A finite retry buffer used while forwarding telemetry to an upstream telemetry
endpoint. When the buffer or retry window is exhausted, telemetry may be
dropped and the gateway should expose that loss as operational signal.
_Avoid_: Durable queue, local archive

**Canary Validation**:
The decision process that compares new workload behavior against expected
telemetry signals before wider rollout.
_Avoid_: Smoke test, rollout dashboard

**Autoscaling Signal**:
A local telemetry-derived signal used to make scaling decisions for workloads.
Cluster Telemetry Bundle exposes the signal substrate; workload teams own the scaling
rules that consume it.
_Avoid_: Alert, dashboard metric

## Example Dialogue

Platform: "The Monitoring Bundle should install the monitoring pieces a
cluster needs, but the Cluster Telemetry Gateway still controls how telemetry is
cached locally and forwarded upstream."

SRE: "So kube-state-metrics can be a Metric Source Profile, and the Local
Validation Cache only needs enough retention for rollout and autoscaling
decisions, not historical investigation."

Platform: "Correct. If upstream is down too long, the Bounded Forwarding Buffer
can drop telemetry, and operators should see that loss through gateway health
signals."
