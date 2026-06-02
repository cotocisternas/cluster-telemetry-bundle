# Cilium And Hubble Monitoring

Cluster Telemetry Bundle can collect Cilium and Hubble metrics without owning the CNI
installation. The profile is a Helm values fragment for a platform-owned
Cilium HelmRelease.

## Ownership

```text
platform owns:
  Cilium lifecycle, CNI policy, Cilium version, datapath settings

cluster-telemetry-bundle owns:
  metric discovery contract, scrape labels, local cache path, upstream path
```

The reusable values live in:

```text
components/cilium-hubble-monitoring/values.yaml
```

The profile enables:

- Cilium agent metrics
- Cilium Envoy metrics
- Cilium Operator metrics
- Hubble flow metrics
- Hubble Relay metrics
- ServiceMonitor labels for Target Allocator discovery

## Runtime Shape

```text
Cilium agent ServiceMonitor ----+
Cilium operator ServiceMonitor -+
Hubble ServiceMonitor ----------+
Hubble Relay ServiceMonitor ----+--> Target Allocator
                                      |
                                      v
                               OTel Collector
                                      |
                    +-----------------+-----------------+
                    |                                   |
                    v                                   v
             VictoriaMetrics                    upstream OTLP/gRPC
```

## Selector Label

All generated ServiceMonitors use:

```yaml
metadata:
  labels:
    telemetry.example.com/scrape: "true"
```

That label is the same selector used by the Target Allocator profile.

## Flux Integration

If the platform-owned Cilium HelmRelease uses Flux, add the generated
ConfigMap as a values source in the same namespace as the Cilium HelmRelease:

```yaml
valuesFrom:
  - kind: ConfigMap
    name: cilium-hubble-monitoring-values
    valuesKey: values.yaml
```

The Cilium HelmRelease usually runs in `kube-system`, so the profile generates
`cilium-hubble-monitoring-values` in `kube-system`.

The values fragment intentionally does not set `k8sServiceHost`,
`k8sServicePort`, IPAM, kube-proxy replacement, or CNI policy. Those are CNI
ownership decisions, not monitoring decisions.

## Kind E2E

The Kind e2e environment installs Cilium with:

```text
test/e2e/cilium/values.yaml
components/cilium-hubble-monitoring/values.yaml
```

That proves the same values profile can produce labeled ServiceMonitors and
feed Cilium/Hubble metrics into the local VictoriaMetrics cache.
