# Monitoring Bundle Profiles

Cluster Telemetry Bundle is a Flux-native monitoring bundle, not only a telemetry gateway.
The bundle should feel close to kube-prometheus-stack in deployment intent: one
package for a cluster's monitoring concerns. It differs in implementation: the
data plane is OpenTelemetry-first, the local metrics cache is VictoriaMetrics,
and configuration is optimized for Flux `valuesFrom` overlays.

## Package Shape

```text
                       Monitoring Bundle

  +-------------------+  +---------------------+  +-------------------+
  | core data plane   |  | metric sources      |  | presentation      |
  +-------------------+  +---------------------+  +-------------------+
  | OTel Collector    |  | Prometheus CRDs     |  | dashboards        |
  | VictoriaMetrics   |  | kube-state-metrics  |  | rules/templates   |
  | Fluent Bit        |  | node-exporter       |  | KEDA examples     |
  |                   |  | Cilium / Hubble     |  |                   |
  +-------------------+  +---------------------+  +-------------------+
           |                      |                       |
           +----------------------+-----------------------+
                                  |
                                  v
                    local cache and upstream OTLP
```

## Profiles

```text
core:
  Always present. Receives OTLP, collects logs, stores short-lived local
  metrics, and forwards all signals upstream.

prometheus-crds:
  Optional. Uses OpenTelemetry Target Allocator to discover selected
  ServiceMonitor and PodMonitor resources.

cluster-state:
  Optional. Deploys kube-state-metrics and publishes a ServiceMonitor selected
  by the Target Allocator.

node-metrics:
  Optional. Deploys prometheus-node-exporter and publishes a ServiceMonitor
  selected by the Target Allocator. Prefer consuming an existing node-exporter
  if the platform already provides one. This profile needs a namespace that
  admits host namespaces and host paths.

cilium-hubble:
  Optional. Does not install or own Cilium. Provides a Cilium Helm values
  fragment that enables Cilium, Cilium Operator, Hubble, and Hubble Relay
  metrics with ServiceMonitor labels selected by the Target Allocator.

presentation:
  Optional. Dashboards, recording rules, alert examples, and KEDA templates.
  These should start as examples because thresholds and alert routing are
  usually platform- or workload-owned.
```

## Comparison With kube-prometheus-stack

```text
Concern                   kube-prometheus-stack        Cluster Telemetry Bundle
------------------------  ---------------------------  --------------------------
Packaging                 One Helm chart               Flux/Kustomize bundle
Primary collector/query   Prometheus                   OTel Collector + VictoriaMetrics
Remote path               Remote write / integrations  OTLP/gRPC upstream
Kubernetes state          kube-state-metrics           cluster-state profile
Node host metrics         node-exporter                node-metrics profile
CNI and flow metrics      Cilium/Hubble                cilium-hubble profile
Dashboards                Grafana defaults             presentation profile
Alerts/rules              PrometheusRule defaults      examples first, defaults later
Scrape CRDs               Prometheus Operator          Target Allocator profile
```

## Default Rule

The default install should remain safe and lean, but not artificially narrow.
New metric sources belong as profiles first. A profile can become default only
when all of these are true:

- It is needed by most clusters.
- It has predictable resource cost.
- It does not duplicate platform-owned monitoring agents.
- It feeds local validation and upstream forwarding through the same data plane.
- It can be configured cleanly through Flux values overlays.

## Current Implementation

```text
base/
  components/
    prometheus-crd-scrape/
      Target Allocator and collector profile for selected ServiceMonitor and
      PodMonitor objects

    kube-state-metrics/
      kube-state-metrics profile with ServiceMonitor label:
      telemetry.example.com/scrape=true

    node-exporter/
      prometheus-node-exporter profile with ServiceMonitor label:
      telemetry.example.com/scrape=true

    cilium-hubble-monitoring/
      Cilium Helm values profile for Cilium, operator, Hubble, and Hubble Relay
      ServiceMonitor labels:
      telemetry.example.com/scrape=true

examples/
  cluster-us-east-1-monitoring-bundle/
    core + prometheus-crds + cluster-state + node-metrics

test/e2e/
  Kind environment with Cilium kube-proxy replacement and Hubble metrics
```

The `cluster-state` and `node-metrics` HelmReleases depend on
`opentelemetry-target-allocator`. Deploy them with the `prometheus-crds` profile
so their ServiceMonitors have an in-bundle discovery path.

Runtime path:

```text
kube-state-metrics ServiceMonitor ----+
node-exporter ServiceMonitor --------+
Cilium / Hubble ServiceMonitor ------+
workload ServiceMonitor / PodMonitor-+--> Target Allocator
                                               |
                                               v
                                        OTel Collector
                                               |
                         +---------------------+---------------------+
                         |                                           |
                         v                                           v
                 VictoriaMetrics                              upstream OTLP/gRPC
```

## Next Recommendation

Add `presentation` as examples before defaults:

- dashboard templates for the local VictoriaMetrics endpoint
- KEDA metric examples that query the `cluster` label
- recording and alert rule examples that platform teams can copy into their
  own rule ownership model

Keep dashboards and rules out of the base until ownership, routing, and
threshold conventions are clear enough to avoid accidental platform policy.
