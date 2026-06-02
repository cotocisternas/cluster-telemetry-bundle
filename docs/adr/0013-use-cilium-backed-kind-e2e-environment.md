# Use Cilium-backed Kind e2e environment

Accepted.

Cluster Telemetry Bundle needs a local e2e environment that validates the full bundle in a
real Kubernetes control plane, not only through local manifest rendering.

## Decision

Add a Kind e2e environment that disables Kind's default CNI and kube-proxy, then
installs Cilium with kube-proxy replacement and Hubble metrics enabled.

Use aqua as the project-local CLI version manager for the e2e command path.
`aqua.yaml` pins Kind, kubectl, Helm 3, and Flux. Docker remains a host
prerequisite because the e2e environment depends on the Docker daemon, not only
the Docker CLI binary.

The e2e environment installs Flux controllers and applies
`test/e2e/overlays/kind-cilium`, which composes:

- the full monitoring bundle example
- Prometheus Operator scrape CRDs through Target Allocator
- kube-state-metrics
- node-exporter
- the Cilium/Hubble monitoring values profile

Cilium remains platform-owned outside this e2e environment. The reusable
production artifact is `base/components/cilium-hubble-monitoring/values.yaml`,
a values fragment that enables Cilium and Hubble ServiceMonitors with the
Target Allocator selector label.

## Consequences

- Local validation can catch Flux, HelmRelease, Cilium, Hubble, ServiceMonitor,
  Target Allocator, collector, and VictoriaMetrics wiring failures.
- The e2e path is heavier than manifest rendering because it requires Docker,
  Kind, Helm, Flux, network access, and Cilium readiness.
- `make tools-install` and `make tools-check` provide a reproducible CLI setup
  path without embedding a curl-based aqua installer in the Makefile.
- The default base remains CNI-neutral.
- The e2e namespace must admit host collectors, so Pod Security `privileged`
  enforcement is expected for the telemetry namespace.
- Production Cilium lifecycle stays outside Cluster Telemetry Bundle ownership.
