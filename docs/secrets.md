# Secrets And Upstream Auth

cluster-telemetry-bundle does not ship default credential Secrets.

The base manifests are deployable without backend credentials because the
default contract is OTLP/gRPC forwarding to a configured upstream endpoint. The
only required per-cluster values are:

- `CLUSTER`: the Prometheus/Grafana-facing cluster label
- `UPSTREAM_OTLP_GRPC_ENDPOINT`: the next upstream OTLP/gRPC endpoint in
  `host:port` form

Set those values through the cluster OTel values override ConfigMap, as shown in
`examples/cluster-us-east-1/otel-values.yaml`.

## When Secrets Are Needed

Add Secrets only in the cluster overlay or platform GitOps repository when the
upstream endpoint requires one of these deployment-specific settings:

- Authorization headers
- Client certificates
- Private CA bundles
- Plaintext compatibility for an upstream that cannot terminate TLS

Do not add default repository-wide credentials for a specific backend. The
gateway contract is the OpenTelemetry upstream endpoint, not ClickHouse,
VictoriaMetrics remote write, or any other storage-specific exporter.

```text
default base:
  OTel Collector --OTLP/gRPC--> upstream endpoint
        |
        +-- no Secret resources rendered by this repo

auth-enabled overlay:
  Secret or ExternalSecret
        |
        v
  env var / mounted file
        |
        v
  otlp/upstream headers or tls settings
        |
        v
  upstream endpoint
```

## Header Auth Pattern

For header-based upstream auth, create the Secret in the overlay and reference it
from an OTel values override:

```yaml
extraEnvs:
  - name: CLUSTER
    value: "cluster-name"
  - name: UPSTREAM_OTLP_GRPC_ENDPOINT
    value: "otel-gateway.example.com:4317"
  - name: UPSTREAM_OTLP_AUTH_HEADER
    valueFrom:
      secretKeyRef:
        name: upstream-otlp-credentials
        key: authorization-header
config:
  exporters:
    otlp/upstream:
      endpoint: "${env:UPSTREAM_OTLP_GRPC_ENDPOINT}"
      headers:
        Authorization: "${env:UPSTREAM_OTLP_AUTH_HEADER}"
```

Store the Secret data with the platform's normal GitOps secret mechanism, such
as SOPS, Sealed Secrets, External Secrets Operator, or pre-provisioned
Kubernetes Secrets.

```text
upstream-otlp-credentials Secret
        |
        | authorization-header
        v
UPSTREAM_OTLP_AUTH_HEADER env var
        |
        v
otlp/upstream.headers.Authorization
```

## TLS Pattern

The base upstream exporter keeps TLS verification enabled:

```yaml
config:
  exporters:
    otlp/upstream:
      tls:
        insecure: false
```

If the upstream uses a private CA, mount that CA into the collector Pod from the
cluster overlay and set `ca_file` on `otlp/upstream`. If the upstream only
supports plaintext, override `tls.insecure` to `true` in that cluster overlay
and keep the exception local to that deployment.

```text
private CA case:
  ConfigMap or Secret with ca.crt
        |
        v
  collector volume mount
        |
        v
  otlp/upstream.tls.ca_file

plaintext exception:
  cluster overlay only
        |
        v
  otlp/upstream.tls.insecure: true
```
