# Per-Cluster Overlay: us-east-1

Example Kustomize overlay demonstrating per-cluster customization of the
cluster-telemetry-bundle module without patching deep Helm values paths.

## Directory Structure

```text
examples/cluster-us-east-1/
|-- kustomization.yaml   # Overlay entry point
|-- otel-values.yaml     # Cluster-specific OTel Helm values
`-- README.md            # This file
```

## How Overrides Work

The base module stores Helm chart values in generated ConfigMaps:

- `opentelemetry-collector-values`
- `victoriametrics-values`
- `fluent-bit-values`

Each HelmRelease also references an optional cluster override ConfigMap:

- `opentelemetry-collector-cluster-values`
- `victoriametrics-cluster-values`
- `fluent-bit-cluster-values`

This overlay generates `opentelemetry-collector-cluster-values` from
`otel-values.yaml`. Flux merges `valuesFrom` entries in order, so the cluster
values override the base values for the same HelmRelease.

```text
../../base/otel-collector/values.yaml
        |
        v
opentelemetry-collector-values
        |
        v
HelmRelease base values
        |
        +---- examples/cluster-us-east-1/otel-values.yaml
                         |
                         v
              opentelemetry-collector-cluster-values
                         |
                         v
              cluster-specific collector config
```

## What This Overlay Customizes

| Area | Base Value | Overlay Value | Why |
|------|------------|---------------|-----|
| Cluster label | `UNSET-OVERRIDE-IN-OVERLAY` | `us-east-1-prod` | Identifies local metrics with the common `cluster` label |
| Upstream OTLP/gRPC endpoint | `upstream-otel-collector.example.com:4317` | `otel-gateway.us-east-1.example.com:4317` | Routes forwarded telemetry to the next upstream hop |
| Sampling percentage | `10` | `5` | Reduces trace volume for a high-traffic cluster |

The overlay does not include credential components. If the upstream requires
auth headers, client certificates, a private CA, or plaintext compatibility,
add that configuration in this overlay or in the platform GitOps repository
that wraps it.

## Rendered Runtime Shape

```text
us-east-1-prod workloads
        |
        | OTLP/gRPC or OTLP/HTTP
        v
OpenTelemetry Collector
        |
        +-- local metrics --> VictoriaMetrics in telemetry namespace
        |
        +-- all signals ----> otel-gateway.us-east-1.example.com:4317

Local metrics labels:
  cluster="us-east-1-prod"

Collector resource attributes:
  k8s.cluster.name="us-east-1-prod"
```

## Creating a New Cluster Overlay

1. Copy this directory:

   ```bash
   cp -r examples/cluster-us-east-1 examples/cluster-eu-west-1
   ```

2. Update `otel-values.yaml`:

   - Change `CLUSTER` to the cluster label expected in Prometheus and Grafana
     queries.
   - Change `UPSTREAM_OTLP_GRPC_ENDPOINT` to the next upstream OTLP/gRPC
     endpoint in `host:port` form.
   - Adjust `sampling_percentage` for cluster traffic volume.
   - Add overlay-only upstream auth or TLS overrides if required.

3. Validate:

   ```bash
   kubectl kustomize examples/cluster-eu-west-1
   ```

4. Verify expected values in the output, replacing `<expected-cluster>` with the
   cluster label you set:

   ```bash
   kubectl kustomize examples/cluster-eu-west-1 | grep -A30 'name: opentelemetry-collector-cluster-values'
   kubectl kustomize examples/cluster-eu-west-1 | grep 'value: "<expected-cluster>"'
   kubectl kustomize examples/cluster-eu-west-1 | grep 'UPSTREAM_OTLP_GRPC_ENDPOINT'
   kubectl kustomize examples/cluster-eu-west-1 | grep 'sampling_percentage'
   ```

## FluxCD Integration

This directory is a local overlay example. Production Flux installs should point
at the reusable root `./` path and provide cluster-specific values from the
platform GitOps repository:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-telemetry-bundle
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: cluster-telemetry-bundle
  path: ./
  prune: true
  interval: 10m
```

Copy this overlay's `opentelemetry-collector-cluster-values` pattern into the
platform repository rather than pointing production Flux at `examples/`.

## Adding More Cluster Overrides

To customize another HelmRelease for a cluster, add a values file and generate
the matching optional ConfigMap name.

For VictoriaMetrics:

```yaml
configMapGenerator:
  - name: victoriametrics-cluster-values
    namespace: telemetry
    files:
      - values.yaml=vm-values.yaml
```

For Fluent Bit:

```yaml
configMapGenerator:
  - name: fluent-bit-cluster-values
    namespace: telemetry
    files:
      - values.yaml=fluent-bit-values.yaml
```

If more than one ConfigMap is generated in the same overlay, put all generator
entries under the same `configMapGenerator` list.

## Prometheus Operator CRDs

This overlay keeps Prometheus Operator CRD scraping disabled. Use
`../cluster-us-east-1-prometheus-crds` when the cluster should collect workload
metrics from `ServiceMonitor` and `PodMonitor` resources.
