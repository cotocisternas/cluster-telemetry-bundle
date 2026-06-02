# Architecture Reference

This document describes the current Cluster Telemetry Bundle shape. It is a
deployment and operations reference; canonical vocabulary remains in
`../CONTEXT.md`, and durable trade-off records remain in `adr/`.

## Product Shape

Cluster Telemetry Bundle is a Flux-native monitoring bundle with a gateway-first data
plane. It is intentionally closer to kube-prometheus-stack in packaging scope
than to a single collector chart, but it swaps the default data plane for OTel
Collector, VictoriaMetrics, and upstream OTLP forwarding.

```text
               Flux-native monitoring bundle

  +--------------------+     +---------------------+
  | metric sources     |     | presentation        |
  | - Prometheus CRDs  |     | - dashboards        |
  | - kube-state-metrics |   | - rules/templates   |
  | - node-exporter    |     | - KEDA examples     |
  | - Cilium / Hubble  |     |                     |
  +----------+---------+     +----------+----------+
             |                          ^
             v                          |
  +--------------------+     +----------+----------+
  | OTel Collector     |---->| VictoriaMetrics     |
  | gateway data plane |     | local cache         |
  +----------+---------+     +---------------------+
             |
             v
  +--------------------+
  | Upstream OTLP/gRPC |
  +--------------------+
```

## Component Topology

```text
                         Kubernetes cluster

     workload OTLP/gRPC or OTLP/HTTP
  +--------------------------------------+
  |                                      |
  v                                      |
+----------------+                       |
| Application    |                       |
| workloads      |                       |
+----------------+                       |
                                         |
                                         v
                                  +-------------+
                                  | OTel        |
container logs                    | Collector   |
+----------------+   OTLP/HTTP    | Deployment  |   OTLP/gRPC
| Fluent Bit     |--------------->|             |----------------+
| DaemonSet      |                +------+------+                |
+----------------+                       |                       |
                                         | OTLP/HTTP metrics     |
                                         v                       v
                                  +-------------+        +----------------+
                                  | Victoria-   |        | Upstream       |
                                  | Metrics     |        | Telemetry      |
                                  | local cache |        | Endpoint       |
                                  +------+------+        +----------------+
                                         ^
                                         |
                                  Prometheus API
                                         |
                                  +------+------+
                                  | Canary and  |
                                  | KEDA rules  |
                                  | outside repo|
                                  +-------------+
```

## Signal Pipelines

```text
Metrics:
  workloads -> OTel Collector -> VictoriaMetrics local cache
                            \-> upstream OTLP/gRPC

Logs:
  containers -> Fluent Bit -> OTel Collector -> upstream OTLP/gRPC
                                      \-> count connector -> local metrics

Traces:
  workloads -> OTel Collector -> error/slow retention + probabilistic sampling
                            \-> upstream OTLP/gRPC

Prometheus metrics:
  ServiceMonitor / PodMonitor -> Target Allocator -> OTel Collector
                                                \-> VictoriaMetrics and upstream

Cilium and Hubble metrics:
  Cilium ServiceMonitors -> Target Allocator -> OTel Collector
                                           \-> VictoriaMetrics and upstream
```

| Signal | Inbound protocol | Local storage | Upstream protocol | Local consumers |
|--------|------------------|---------------|-------------------|-----------------|
| Metrics | OTLP/gRPC, OTLP/HTTP | VictoriaMetrics | OTLP/gRPC | Canary checks, KEDA rules |
| Prometheus metrics | ServiceMonitor, PodMonitor | VictoriaMetrics | OTLP/gRPC | Canary checks, KEDA rules |
| Cilium/Hubble metrics | ServiceMonitor | VictoriaMetrics | OTLP/gRPC | CNI health, flow checks |
| Logs | Fluent Bit OTLP/HTTP | None | OTLP/gRPC | Derived metrics only |
| Traces | OTLP/gRPC, OTLP/HTTP | None | OTLP/gRPC | None |

## Pod Security Boundary

The bundle's `telemetry` namespace uses Pod Security `privileged` enforcement.
This is required by the current base install because Fluent Bit tails container
logs from host paths. The `node-metrics` profile also needs host namespaces and
host paths for prometheus-node-exporter.

```text
telemetry namespace
  Pod Security: privileged enforce, baseline warn/audit
        |
        +-- Fluent Bit host log collection
        +-- node-exporter host metrics profile
        +-- OTel Collector and VictoriaMetrics
```

If a platform needs stricter policy isolation, split host collectors into their
own privileged namespace and keep collector/cache workloads in a more restrictive
namespace.

## Local Validation Cache

The local cache is deliberately small and disposable.

```text
                  local validation path

  OTel Collector --metrics--> VictoriaMetrics --Prometheus API--> consumers
                                      |
                                      +-- retention: 24h
                                      +-- persistence: disabled by default
                                      +-- purpose: rollout and scaling checks
```

The cache is not the source of truth for historical observability. It exists so
cluster-local automation can keep working when upstream visibility is delayed or
temporarily unavailable.

## Prometheus CRD Scraping

Prometheus Operator CRD scraping is an optional extension. It is not enabled in
the base install because it requires the Prometheus Operator CRDs and an extra
discovery component.

```text
metadata.label:
  telemetry.example.com/scrape=true

ServiceMonitor / PodMonitor
        |
        v
OpenTelemetry Target Allocator
        |
        v
OTel Collector prometheus receiver
        |
        +-- metrics/prometheus-crds pipeline
        |
        +-- VictoriaMetrics local cache
        |
        +-- upstream OTLP/gRPC
```

This path is for application metrics that are already exposed in Prometheus
format. It is separate from gateway self-monitoring, where an external
Prometheus stack may scrape collector or VictoriaMetrics component metrics with
the charts' disabled-by-default `ServiceMonitor` hooks.

## Metric Source Profiles

Metric source profiles package common cluster monitoring sources without making
them part of the lean base install.

```text
                        source profiles

  +----------------------+       +---------------------------+
  | kube-state-metrics   |       | prometheus-node-exporter  |
  | Kubernetes objects   |       | node host metrics         |
  +----------+-----------+       +-------------+-------------+
             |                                 |
             | ServiceMonitor                  | ServiceMonitor
             | telemetry.example.com/scrape    | telemetry.example.com/scrape
             +----------------+----------------+
                              |
                              v
                    Target Allocator profile
                              |
                              v
                         OTel Collector
                              |
              +---------------+----------------+
              |                                |
              v                                v
        VictoriaMetrics                 upstream OTLP/gRPC
```

The profile bases are:

- `base/components/kube-state-metrics`
- `base/components/node-exporter`

Both use Prometheus Community OCI charts and Flux `valuesFrom` ConfigMaps.
Both expose optional cluster override ConfigMaps:

```text
kube-state-metrics-cluster-values
node-exporter-cluster-values
```

The combined example is `examples/cluster-us-east-1-monitoring-bundle`. It
includes the Prometheus CRD scraping profile so the generated ServiceMonitors
are discovered by the Target Allocator.

## Cilium And Hubble Monitoring

Cilium is platform infrastructure, not a component owned by the monitoring
bundle. Cluster Telemetry Bundle owns the monitoring contract for Cilium metrics by
providing a values profile that a platform-owned Cilium HelmRelease can consume.

```text
platform-owned Cilium HelmRelease
        |
        | valuesFrom or values file:
        | base/components/cilium-hubble-monitoring/values.yaml
        v
Cilium agent, operator, Hubble, Hubble Relay metrics
        |
        | ServiceMonitor label:
        | telemetry.example.com/scrape=true
        v
Target Allocator -> OTel Collector -> VictoriaMetrics + upstream OTLP
```

The local e2e environment installs Cilium into Kind with kube-proxy replacement
and Hubble metrics enabled, then applies `test/e2e/overlays/kind-cilium` through
Flux. This exercises the same ServiceMonitor path as the source profiles while
keeping CNI ownership outside the default bundle.

## Upstream Forwarding

The upstream contract is OTLP/gRPC from the OTel Collector to the next telemetry
hop.

```text
        +----------------+
        | OTel Collector |
        +-------+--------+
                |
                | otlp/upstream
                | endpoint: UPSTREAM_OTLP_GRPC_ENDPOINT
                | tls.insecure: false by default
                |
                v
        +-----------------------------+
        | Upstream Telemetry Endpoint |
        +-----------------------------+
```

The collector uses bounded sending queues and retry windows. During a short
upstream outage, telemetry can wait in memory. During a long outage or sustained
overload, the collector may drop telemetry after queue or retry limits are
exhausted.

```text
upstream healthy:
  receive -> process -> forward -> accepted

short outage:
  receive -> process -> queue -> retry -> forward

long outage:
  receive -> process -> queue full or retry expired -> drop
                                              |
                                              v
                                  collector exporter failure metrics
```

## Identity Model

Each cluster overlay sets the operator-chosen cluster value.

```text
examples/<cluster>/otel-values.yaml
        |
        | CLUSTER=us-east-1-prod
        v
OTel resource processor
        |
        +-- resource attribute: cluster=us-east-1-prod
        +-- resource attribute: k8s.cluster.name=us-east-1-prod
        |
        v
local Prometheus-compatible metrics use label: cluster
```

Use `cluster` for Prometheus, Grafana, canary validation, and KEDA selectors.
Keep `k8s.cluster.name` and `k8s.cluster.uid` for OpenTelemetry consumers.

## Configuration Layering

Kustomize owns composition. Flux HelmRelease owns chart installation. The repo
keeps Helm values in plain files and feeds them through generated ConfigMaps.

```text
base values file
  base/otel-collector/values.yaml
        |
        v
generated ConfigMap
  opentelemetry-collector-values
        |
        v
HelmRelease valuesFrom[0]

optional cluster values file
  examples/cluster-us-east-1/otel-values.yaml
        |
        v
generated ConfigMap
  opentelemetry-collector-cluster-values
        |
        v
HelmRelease valuesFrom[1]

final chart values:
  base values merged first, cluster values merged second
```

Cluster overlays should prefer values files and generated ConfigMaps over JSON
patches against deeply nested HelmRelease values.

## Ownership Boundary

```text
+----------------------------------+  +--------------------------------+
| cluster-telemetry-bundle owns               |  | platform/workload teams own    |
+----------------------------------+  +--------------------------------+
| telemetry namespace              |  | workload instrumentation       |
| OTel Collector deployment        |  | upstream telemetry backend     |
| Fluent Bit deployment            |  | upstream auth material         |
| VictoriaMetrics local cache      |  | canary policy definitions      |
| metric source profile packaging  |  | KEDA ScaledObjects             |
| Flux HelmRelease wiring          |  | alert routing and thresholds   |
| base and overlay value hooks     |  | final dashboard ownership      |
+----------------------------------+  +--------------------------------+
```

This boundary lets the module become a monitoring bundle without becoming a
central observability platform. It can package kube-state-metrics and
node-exporter profiles while still routing data through the same local cache and
upstream telemetry path.
