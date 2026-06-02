# Flux Remote Source Examples

These examples show how a platform GitOps repository can deploy
Cluster Telemetry Bundle from the public upstream repository:

```text
Flux GitRepository
  url: https://github.com/cotocisternas/cluster-telemetry-bundle.git
        |
        v
Flux Kustomization
  path: ./examples/cluster-us-east-1
  components:
    ../../base/components/<optional-profile>
```

## Examples

```text
core/
  Remote core bundle example.

prometheus-crds/
  Remote core bundle plus Prometheus Operator ServiceMonitor/PodMonitor
  scraping through Target Allocator.

monitoring-bundle/
  Remote core bundle plus Prometheus CRD scraping, kube-state-metrics, and
  node-exporter.
```

These are documentation examples for a consuming GitOps repository. Real
clusters should copy the pattern and point `path` at their own cluster overlay
when cluster-specific endpoint, identity, TLS, or authentication values differ
from the public examples.
