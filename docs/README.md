# Documentation Guide

Use this guide to find the right document before changing the gateway.

```text
README.md
  |
  +-- docs/architecture.md
  |     |
  |     +-- component topology
  |     +-- signal pipelines
  |     +-- local cache and upstream behavior
  |     +-- configuration layering
  |
  +-- docs/secrets.md
  |     |
  |     +-- upstream auth and TLS overlay patterns
  |
  +-- docs/prometheus-operator-crds.md
  |     |
  |     +-- ServiceMonitor and PodMonitor scraping
  |
  +-- docs/cilium-hubble-monitoring.md
  |     |
  |     +-- Cilium and Hubble metric profile
  |
  +-- docs/kind-e2e.md
  |     |
  |     +-- local Kind/Cilium e2e environment
  |
  +-- docs/monitoring-bundle-profiles.md
  |     |
  |     +-- kube-prometheus-stack comparison and profile model
  |
  +-- docs/adr/
        |
        +-- accepted decisions and trade-offs
```

## Reading Order

```text
new operator:
  README.md -> examples/cluster-us-east-1/README.md -> docs/secrets.md

architecture change:
  CONTEXT.md -> docs/architecture.md -> relevant ADRs

bundle/profile change:
  CONTEXT.md -> docs/monitoring-bundle-profiles.md -> docs/architecture.md -> relevant ADRs

cluster overlay change:
  README.md -> examples/cluster-us-east-1/README.md -> component values file

Prometheus CRD scraping:
  docs/prometheus-operator-crds.md -> examples/cluster-us-east-1-prometheus-crds/README.md

full monitoring bundle:
  docs/monitoring-bundle-profiles.md -> examples/cluster-us-east-1-monitoring-bundle/README.md

Flux remote source:
  examples/flux/README.md -> examples/flux/monitoring-bundle

Cilium/Hubble metrics:
  docs/cilium-hubble-monitoring.md -> base/components/cilium-hubble-monitoring/values.yaml

Kind e2e:
  docs/kind-e2e.md -> Makefile -> test/e2e/overlays/kind-cilium
```

## Decision Map

```text
GitOps packaging:
  ADR-0001 -> Flux valuesFrom over umbrella Helm

telemetry product shape:
  ADR-0002 -> local cache is metrics-only
  ADR-0003 -> upstream forwarding is OTLP/gRPC
  ADR-0004 -> OTel Collector is the application telemetry front door
  ADR-0005 -> VictoriaMetrics serves local validation metrics
  ADR-0006 -> logs and traces are processed without local storage
  ADR-0007 -> receive OTLP/gRPC and OTLP/HTTP

operational boundaries:
  ADR-0008 -> expose metrics, do not own rollout rules
  ADR-0009 -> bounded buffering during upstream outages
  ADR-0010 -> use cluster for metrics identity
  ADR-0011 -> support ServiceMonitor and PodMonitor with Target Allocator
  ADR-0012 -> model as Flux-native monitoring bundle
  ADR-0013 -> use Cilium-backed Kind e2e environment
```

Keep implementation details out of `CONTEXT.md`. It is the glossary. Put durable
trade-offs in ADRs and operational diagrams in `docs/architecture.md`.
