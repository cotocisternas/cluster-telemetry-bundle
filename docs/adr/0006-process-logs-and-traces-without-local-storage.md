# Process logs and traces without local storage

Accepted.

Cluster Telemetry Bundle processes logs and traces locally for enrichment, scrubbing,
sampling, and upstream protection, but does not store them in the Local
Validation Cache. Logs and traces are forwarded to the upstream telemetry
endpoint over the upstream OTLP path.

## Consequences

The gateway may apply trace sampling and attribute policy before forwarding.
It should not expose local log or trace query surfaces, and it should not deploy
local log or trace storage as part of the default bundle.
