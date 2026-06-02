# Flux Copy-Paste Examples

These directories are meant to be copied into a platform Flux repository. Each
directory contains a complete `GitRepository` and Flux `Kustomization` pair that
pulls Cluster Telemetry Bundle from the public upstream repository.

The Flux `Kustomization` points at `./base`, and optional profiles are selected
with Flux `.spec.components`. Component paths are relative to `./base` inside the
fetched source artifact.

This follows the Flux Kustomization components contract: component paths must be
local and relative to `.spec.path`. See the Flux docs:
https://fluxcd.io/flux/components/kustomize/kustomizations/#components

```text
your Flux repo
  clusters/prod/telemetry/
    kustomization.yaml
    source.yaml
    bundle.yaml

source.yaml
  GitRepository:
    url: https://github.com/cotocisternas/cluster-telemetry-bundle.git

bundle.yaml
  Kustomization:
    sourceRef: cluster-telemetry-bundle
    path: ./base
    components:
      - components/prometheus-crd-scrape
      - components/kube-state-metrics
      - components/node-exporter
```

## Examples

```text
core/
  Deploys the reusable base bundle:
  path: ./base

prometheus-crds/
  Deploys the reusable base bundle with Prometheus Operator
  ServiceMonitor/PodMonitor scraping. This example also creates
  opentelemetry-target-allocator-cluster-values to use a custom scrape
  selector:
  path: ./base
  components:
    - components/prometheus-crd-scrape
  local ConfigMap:
    opentelemetry-target-allocator-cluster-values:
      targetAllocator.config.prometheus_cr selector:
        observability.example.com/scrape=enabled

monitoring-bundle/
  Deploys the reusable base bundle with Prometheus CRD scraping,
  kube-state-metrics, and node-exporter:
  path: ./base
  components:
    - components/prometheus-crd-scrape
    - components/kube-state-metrics
    - components/node-exporter
```

## Production Customization

The standard Helm values override pattern is an optional `*-cluster-values`
ConfigMap in the same namespace as the HelmRelease. Flux HelmController merges
base values first and cluster values second.

```text
base values ConfigMap
        |
        v
HelmRelease valuesFrom[0]
        |
        +---- optional *-cluster-values ConfigMap
                         |
                         v
              HelmRelease valuesFrom[1]
```

Use this pattern for cluster identity, upstream endpoints, resources,
tolerations, scrape selectors, and other chart values. The current optional
cluster values hooks are:

```text
opentelemetry-collector-cluster-values
victoriametrics-cluster-values
fluent-bit-cluster-values
opentelemetry-target-allocator-cluster-values
kube-state-metrics-cluster-values
node-exporter-cluster-values
```

The base values use documentation placeholder values such as
`upstream-otel-collector.example.com:4317`. For a real cluster, publish the
needed `*-cluster-values` ConfigMaps in the `telemetry` namespace or maintain
an internal overlay repository that extends this bundle.

The `prometheus-crds` example demonstrates this pattern by creating
`opentelemetry-target-allocator-cluster-values`. It changes the Target
Allocator selector from the bundle default:

```text
telemetry.example.com/scrape=true
```

to this copy-paste placeholder:

```text
observability.example.com/scrape=enabled
```

Workload `ServiceMonitor` and `PodMonitor` objects must use the same label:

```yaml
metadata:
  labels:
    observability.example.com/scrape: "enabled"
```

For `monitoring-bundle`, keep the default selector unless you also override the
kube-state-metrics and node-exporter ServiceMonitor labels to match.

Keep the copy-paste Flux shape the same:

```text
GitRepository -> path: ./base -> optional components relative to ./base
local Flux repo -> optional *-cluster-values ConfigMaps
```

Do not point `path` at this repository's `examples/` directories for production
Flux installs. The examples are local render fixtures and documentation aids;
the reusable deployment entrypoint is `./base`.
