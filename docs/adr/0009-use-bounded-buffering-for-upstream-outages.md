# Use bounded buffering for upstream outages

Accepted.

Cluster Telemetry Bundle uses bounded buffering and retry for upstream telemetry delivery.
If the upstream telemetry endpoint is unavailable beyond configured limits, the
gateway may drop telemetry and must expose queue, retry, and drop signals for
operators.

```text
healthy:
  receive -> process -> forward

temporary outage:
  receive -> process -> queue -> retry -> forward

extended outage:
  receive -> process -> queue full or retry expired -> drop signal
```

## Consequences

The Local Validation Cache continues serving short-lived metrics for canary
validation and autoscaling, but it is not a durability mechanism for all
telemetry. The gateway should prefer predictable resource use and explicit loss
visibility over unbounded disk or memory growth.
