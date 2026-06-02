# Receive OTLP/gRPC and OTLP/HTTP

Accepted.

Cluster Telemetry Bundle accepts application telemetry over both OTLP/gRPC and OTLP/HTTP.
OTLP/gRPC is the preferred inbound protocol for instrumented services and
collector-to-collector traffic, while OTLP/HTTP remains supported for clients
and environments where HTTP is the practical option.

## Consequences

The collector should expose the standard OTLP/gRPC and OTLP/HTTP receiver
ports. Documentation and examples should prefer gRPC where the sender supports
it, while keeping HTTP as a supported collection path.
