# Use Flux valuesFrom for chart values

Accepted.

cluster-telemetry-bundle is consumed as a Flux GitOps module, so it keeps Kustomize as the
composition layer and Flux HelmRelease as the chart installation layer instead
of introducing an umbrella Helm chart. Helm chart values live in generated
ConfigMaps referenced through `valuesFrom`, with optional per-cluster override
ConfigMaps merged after the base values; this preserves Flux-native
reconciliation while avoiding fragile JSON patches into nested chart value
arrays.

Generated values ConfigMaps use stable names and the
`reconcile.fluxcd.io/watch: Enabled` label so Helm reconciles when values
change without requiring Kustomize nameReference configuration for HelmRelease
CRDs.

```text
base values file
        |
        v
base generated ConfigMap
        |
        v
HelmRelease valuesFrom[0]
        |
        +---- optional cluster values file
                         |
                         v
              cluster generated ConfigMap
                         |
                         v
              HelmRelease valuesFrom[1]
```

## Consequences

Cluster overlays should add or edit values files rather than patching
`spec.values` internals. Because Helm list values are replaced as whole lists
during merges, overlays that customize arrays must provide the intended full
list for that field.
