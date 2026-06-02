# Forward upstream with OTLP/gRPC

Accepted.

Cluster Telemetry Bundle forwards telemetry to the next upstream telemetry endpoint using
OTLP/gRPC by default. OTLP/HTTP is allowed only as an explicit compatibility
override for upstreams that cannot receive gRPC.

```text
metrics ----+
logs -------+--> OTel Collector --OTLP/gRPC--> Upstream Telemetry Endpoint
traces -----+
```

## Consequences

The upstream path should be signal-uniform: metrics, logs, and traces leave the
Cluster Telemetry Gateway through OTel Collector OTLP exporters. Product design
should not treat VictoriaMetrics remoteWrite or backend-specific exporters as
the primary upstream forwarding contract.
