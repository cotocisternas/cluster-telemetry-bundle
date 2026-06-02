# Repository Review — cluster-telemetry-bundle

> Original status: review only. No code was changed to produce this document.
> Method: 8 independent expert lenses + adversarial verification of every
> high-impact correctness/security claim against real OpenTelemetry Collector,
> Target Allocator, VictoriaMetrics, and Flux behavior (docs, source, and
> empirical render tests).
> Scope reviewed: all manifests under `base/`, `examples/`, `test/`, the
> `Makefile`, `scripts/`, `aqua.yaml`, and all of `docs/` including the 13 ADRs.

> Maintainer update (2026-06-02): valid low-risk findings were implemented in
> this repository after the original review. The update also corrects the
> VictoriaMetrics delta-temporality and Flux chart-verification claims that did
> not hold under follow-up verification.

## Table Of Contents

- [1. What This Repository Is](#1-what-this-repository-is)
- [2. Overall Assessment](#2-overall-assessment)
- [3. How To Read The Severities](#3-how-to-read-the-severities)
- [4. High-Severity Findings](#4-high-severity-findings)
- [5. Medium-Severity Findings](#5-medium-severity-findings)
- [6. Low-Severity Findings](#6-low-severity-findings)
- [7. Verified Non-Issues (Do Not "Fix")](#7-verified-non-issues-do-not-fix)
- [8. Strengths (Do Not Regress)](#8-strengths-do-not-regress)
- [9. Refactors](#9-refactors)
- [10. Future Features / Roadmap](#10-future-features--roadmap)
- [11. Implementation Plan](#11-implementation-plan)
- [Appendix A. Finding Index](#appendix-a-finding-index)

---

## 1. What This Repository Is

A **Flux-native GitOps monitoring bundle**: Kustomize bases/overlays/components
plus Flux `HelmRelease`/`HelmRepository` plus plain Helm values files. There is
no application source code; "correctness" lives in config semantics (selector
matching, pipeline graphs, dependency ordering, chart version safety, Pod
Security), which a `kubectl kustomize` render does not validate.

It is positioned as a `kube-prometheus-stack` peer with an OpenTelemetry-first
data plane.

| Concern | Implementation |
|---|---|
| Ingest | OTel Collector (Deployment ×3), OTLP gRPC `:4317` / HTTP `:4318` |
| Local cache | VictoriaMetrics single, 24h retention, persistence **off** (ephemeral by design) |
| Logs | Fluent Bit DaemonSet → collector OTLP/HTTP; `count` connector derives `http_5xx_errors_total` |
| Traces | tail sampling (retain 4xx/5xx/slow + probabilistic baseline) → upstream OTLP/gRPC |
| Upstream | bounded sending queue + retry, TLS-on by default |
| Metric-source profiles | Kustomize components: `prometheus-crd-scrape` (Target Allocator), `kube-state-metrics`, `node-exporter`, `cilium-hubble-monitoring` |
| Composition | `base/` → `examples/cluster-*` overlays → `examples/flux/*` remote-source → `test/e2e/overlays/kind-cilium` |
| Validation | `make manifests-check` (render only), `scripts/check-e2e-kind.sh` (grep invariants), full Kind + Cilium + Flux e2e |
| Docs | 13 ADRs, `CONTEXT.md` glossary, architecture reference, profile model, reading-order map |

The conceptual discipline (ADRs, glossary, ownership boundary, profile model) is
well above the norm for an infrastructure repo. The findings below are about
runtime config semantics and process, not sloppiness.

## 2. Overall Assessment

**Strong design and documentation, with a small number of real correctness
bugs, several production-hardening gaps, and one large process gap (no CI).**

The single most important issue was that the **trace path was statistically
incorrect under replication** (tail sampling across 3 replicas with no
trace-ID-aware routing). The second is that the **derived log metric depends on
an unproven Fluent Bit attribute contract**; the earlier claim that the pinned
VictoriaMetrics drops delta temporality was false for the resolved chart. The
third is **release/validation process**: chart versions floated on patch
wildcards with an hourly re-poll and no CI, schema validation, or dependency
automation.

### Why adversarial verification mattered

Verification refuted two confident-looking "bugs" — a reminder that in config
repos, a plausible defect and a real one look identical until you check the
runtime behavior:

- **`collector_id: ${env:OTEL_K8S_POD_NAME}`** appeared broken because the env
  var is never defined in any values file. But the pinned collector chart
  (`0.147.2`, the highest match for `0.147.x`) injects it unconditionally via
  the Downward API. It works. Only the floating `.x` range makes it *latent*.
- **`collector_selector: matchlabels:`** (lowercase) looked like the classic
  case-sensitivity discovery bug. But the Target Allocator's
  `MapToLabelSelector` decode hook normalizes camelCase **down** to lowercase,
  so `matchlabels` is the natively-correct form (upstream issue #3350 is the
  reverse failure). A "fix it and add a reject-rule" change would have
  introduced a regression on older Target Allocator versions.

Both are documented in [Section 7](#7-verified-non-issues-do-not-fix).

## 3. How To Read The Severities

Severities are calibrated to a GitOps infrastructure bundle meant to be copied
across clusters. A selector that silently matches nothing, a sampling
correctness break, a data-loss window, or a silent supply-chain auto-adopt is
high. Cosmetic drift is low.

Where the multi-agent review and the adversarial verifier disagreed, this
document uses the **verified** severity and notes the correction inline.

```text
🔴 HIGH     correctness / safety / supply-chain — fix before relying on the feature
🟠 MEDIUM   hardening, scale, scope, or doc drift that misleads operators
🟡 LOW      polish, clarity, opt-in hardening
✅ NON-ISSUE verified false positive — changing it would add risk or noise
```

### Implementation Status

Implemented in the follow-up patch:

- H1 interim safety: collector `replicaCount: 1` while `tail_sampling` remains
  single-tier.
- H3/M13: exact Helm chart pins plus collector image tag and digest.
- H4: GitHub Actions CI, kubeconform schema validation, Helm template checks,
  rendered invariant checks, and `otelcol validate`.
- H5/M1/L4/L9/L10: collector PDB, topology spread, NetworkPolicy, non-root
  read-only security context, absolute memory limiter bounds, and
  `metrics/from_logs` memory limiter.
- M2/M4/M6/M8/M11/M12/L3/L6: fail-fast cluster sentinel, reduced derived-metric
  labels, bounded Fluent Bit disk buffering with unbounded delivery retry,
  reconciled Flux guidance, vendored e2e Prometheus Operator CRDs, selector
  alignment, and agent-doc gitignore cleanup.

Still future work:

- Full two-tier trace topology.
- E2E synthetic 5xx log proof for `http_5xx_errors_total`.
- Optional chart signature verification once publishers' chart signing support
  is confirmed.
- Dedicated scrape collector, presentation profile, kubelet/cAdvisor/apiserver
  scrape profile, optional durable queues, and optional namespace split.

## 4. High-Severity Findings

### H1 · Tail sampling was statistically broken at `replicaCount: 3`

- **Where:** `base/otel-collector/values.yaml:8-9` (`mode: deployment`,
  formerly `replicaCount: 3`), `:71` (`tail_sampling`), `:180` (traces
  pipeline).
- **Status:** valid; remediated with the interim safe topology
  `replicaCount: 1`. A two-tier trace-ID-routed topology is still the scalable
  target.
- **What happens:** three replicas sit behind a round-robin ClusterIP with no
  trace-ID-aware routing — there is no `loadbalancing` exporter, no second tier,
  no `routing_key: traceID` anywhere (grep-confirmed empty). A distributed trace
  is produced by many client pods, whose spans land on different replicas. Each
  replica runs `tail_sampling` on only the fragment it received: `retain-5xx`
  and `retain-slow` miss spans that landed elsewhere, and the probabilistic
  baseline is applied per-fragment. The result is silently wrong/incomplete
  sampled data forwarded upstream — no error is emitted. The production overlay
  `examples/cluster-us-east-1` inherits this.
- **Fix:** adopt the canonical two-tier topology — a stateless ingest tier
  (Deployment, can stay ×3) whose traces pipeline uses the `loadbalancing`
  exporter with `routing_key: traceID` against a **headless** Service, fanning
  out to a tail-sampling tier (separate Deployment/StatefulSet) that runs the
  existing `tail_sampling`. Simpler interim: set the trace-handling collector to
  `replicaCount: 1`. Record the decision in a new ADR.
- **Do not:** rely on adding `groupbytrace` alone — it only groups spans within
  a single instance and cannot pull spans that landed on the other replicas.

### H2 · `http_5xx_errors_total` has an unproven log attribute contract

- **Where:** `base/otel-collector/values.yaml:150-162` (`count` connector),
  `:186-189` (`metrics/from_logs` pipeline).
- **Status:** partially valid; corrected from High to Medium. The delta-drop
  mechanism was wrong. The resolved `victoria-metrics-single` chart `0.33.0`
  uses VictoriaMetrics `v1.138.0`, while VictoriaMetrics documents OTLP delta
  temporality storage as supported since `v1.132.0`.
- **What happens:** the count condition
  `attributes["http.response.status_code"] >= 500` assumes a numeric
  OTel-semconv log attribute. Fluent Bit's Kubernetes filter does not guarantee
  that attribute by default, so this metric still needs an end-to-end test with
  a synthetic 5xx log.
- **Fix:** assert the Fluent Bit-to-collector contract in e2e; add a
  transform/attributes step only if the test shows the field is absent or typed
  as a string. Keep `deltatocumulative` as an optional compatibility processor
  for downstreams that require cumulative streams, not as a VM-ingestion fix.

### H3 · Supply chain — floating `.x` pins + hourly OCI re-poll, no review gate

- **Where:** every `HelmRelease` (`0.147.x`, `0.33.x`, `0.56.x`, `0.127.x`,
  `7.4.x`, `4.55.x`); OCI `HelmRepository` `interval: 1h`. Flux GitRepository
  examples track `ref.branch: main` (re-checked every `1m`). No
  cosign/digest/verify anywhere.
- **Status:** core confirmed; the originally-proposed fix was partially wrong
  and is corrected below.
- **What happens:** a patch wildcard resolves to the latest matching patch, and
  Flux re-resolves it on the 1h interval. A newly published, yanked, or
  compromised upstream patch auto-rolls to every consuming cluster within ~1h
  with no human review and no integrity gate. The canonical examples model the
  least-reproducible pattern (`branch: main`).
- **Fix (priority order):**
  1. **Pin exact versions** (e.g. `0.147.2`) and add **Renovate or Dependabot**
     to bump them via reviewed PRs. This removes the silent auto-adopt and is
     fully in maintainer control.
  2. For integrity, enable Helm chart verification only after confirming each
     publisher signs its chart artifacts. Flux supports this on the HelmChart
     template created from `HelmRelease.spec.chart.spec.verify` for OCI-backed
     Helm charts. Migrating to `OCIRepository` + `chartRef` is still a valid
     modernization path, but it is not required merely to use chart
     verification.
  3. Show `ref.tag`/`ref.commit` pinning in at least one Flux example and
     recommend it for production; `branch: main` is for dev/e2e only.

### H4 · No CI; validation is render-only

- **Where:** no `.github/`. `Makefile` `manifests-check` pipes
  `kubectl kustomize` to `/dev/null`. `scripts/check-e2e-kind.sh` is
  grep-on-substrings. The full e2e needs Docker + cgroup v2 + kernel 5.14+.
- **Status:** confirmed empirically — a manifest with `apiVersion: .../v9`,
  a typo `kind:`, and a bogus field rendered with exit code 0.
- **What happens:** `kubectl kustomize` checks templating/merge, not schema
  validity, not the OTel config, not chart values. A malformed Flux CR passes
  every cheap check and fails only at apply/reconcile. The grep harness gives
  false confidence; the real e2e cannot gate PRs in most hosted CI.
- **Fix:** a PR workflow that runs:
  - `make manifests-check` piped through **kubeconform** (`-strict`,
    `-schema-location default` + the datreeio/CRDs-catalog template for Flux
    types), pinned in `aqua.yaml`;
  - **`otelcol validate`** on the rendered collector config (pinned
    `otel/opentelemetry-collector-k8s` image matching the chart);
  - **`flux build` / `helm template`** to catch invalid chart values that
    kubeconform cannot see (they live inside generated ConfigMaps);
  - `yamllint`.
  Keep the heavy Kind e2e on a nightly/self-hosted runner.
  Note: `otelcol validate` will **not** catch H1 (a valid config, broken
  topology) — pair it with a static assertion that `tail_sampling` is never
  combined with `replicaCount > 1` without trace-ID routing.

### H5 · No HA primitives for the data plane

- **Where:** repo-wide grep for `PodDisruptionBudget`, `topologySpread`,
  `affinity` returns nothing. Collector `replicaCount: 3`; VictoriaMetrics
  single replica.
- **What happens:** the 3 collector replicas can be co-scheduled and all evicted
  by one node drain (no PDB, no spread) — a maintenance window drops all ingest.
  VictoriaMetrics is a single replica with no PDB, so a drain takes the entire
  canary/KEDA read path offline; with persistence off, that reschedule is also a
  total cache loss. The ephemerality is a deliberate, documented decision
  (ADR-0002/0005) — the gap is the **missing PDB + anti-affinity**, not the
  ephemerality.
- **Fix:** add PDBs (collector `maxUnavailable: 1`, VM `minAvailable: 1`) and
  `topologySpreadConstraints` for the collector — all native chart values.

## 5. Medium-Severity Findings

| # | Finding | Evidence | Fix |
|---|---|---|---|
| M1 | **Collector was not explicitly hardened** (empty `securityContext`) under namespace-wide `privileged` PSS. The earlier "runs as root" wording was not proven from repo values alone. | `base/shared/namespace.yaml:10`; prior collector values had no securityContext | Add a hardened `securityContext` to the collector (runAsNonRoot, drop ALL, readOnlyRootFilesystem, seccomp RuntimeDefault); split host collectors (Fluent Bit, node-exporter) into a separate privileged namespace and keep `telemetry` at `baseline`/`restricted` |
| M2 | **`CLUSTER=base-cluster` silent default** — an overlay that forgets to override mislabels all metrics; two such clusters collide on the `cluster` label upstream and in VM | `base/otel-collector/values.yaml:4-5` | Replace with a fail-fast sentinel (e.g. `UNSET-OVERRIDE-IN-OVERLAY`) plus a render assertion that no overlay emits `cluster=base-cluster`/`UNSET`; document as a required overlay step |
| M3 | Fluent Bit `tolerations: [{operator: Exists}]` schedules the log tailer on **control-plane nodes** (apiserver/etcd/controller logs) with a writable hostPath | `base/fluent-bit/values.yaml:1-2,8-14` | Narrow tolerations to the taints actually required; decide intent on control-plane log collection; mount `/var/log` read-only |
| M4 | `count` connector keeps `http.route` → **cardinality blow-up** risk in a 512Mi–1Gi cache with persistence off; no documented consumer | `base/otel-collector/values.yaml:150-162` | Make `http.route` opt-in or add a metricRelabel cap; document a consuming PromQL (`sum by (cluster,service.name)(rate(http_5xx_errors_total[5m]))`) |
| M5 | Collector **CPU limit 250m** likely CFS-throttles under tail-sampling + gzip + OTTL; `memory_limiter` 80%+15% leaves ~5% headroom vs the 512Mi hard limit | `base/otel-collector/values.yaml:10-16,61-62` | Raise/remove the CPU limit; pin `limit_mib`/`spike_limit_mib` absolute (e.g. 400/80) instead of percentages; load-test in e2e |
| M6 | Fluent Bit `Retry_Limit 5` + `pause_on_chunks_overlimit On` = silent log loss vs node-disk-pressure tradeoff, undocumented | `base/fluent-bit/values.yaml:44,91` | `Retry_Limit False` + bound disk via `storage.total_limit_size` rather than pausing input; document the chosen tradeoff |
| M7 | Single-tier collector also runs Target-Allocator Prometheus scraping — scrape load, OTLP ingest, and tail sampling share one workload and scaling domain; TA scrape collectors conventionally want stable StatefulSet identity | `base/components/prometheus-crd-scrape/otel-collector-values.yaml` | Split a dedicated StatefulSet scrape collector fed by the TA, distinct from the OTLP ingest Deployment |
| M8 | **Contradictory Flux deploy guidance**: `examples/cluster-us-east-1/README.md` points production Flux at `examples/`, but `README.md` and `examples/flux/README.md` forbid exactly that | cross-doc | Point the overlay README at `./base` + a local cluster-values ConfigMap, or mark it demonstration-only |
| M9 | **`presentation` profile** (dashboards, PrometheusRule, KEDA examples) referenced in three docs but **not implemented** | `README.md:89`, `docs/monitoring-bundle-profiles.md:55-150` | Ship `base/components/presentation` as examples-first (Grafana JSON, sample rules, sample KEDA ScaledObject keyed on `cluster`) |
| M10 | `kube-prometheus-stack` parity claimed but **no kubelet/cAdvisor/apiserver scraping** — per-container metrics (the autoscaling substrate) have no path | `docs/monitoring-bundle-profiles.md:61-75`, `README.md:55-68` | Add a kubelet/cAdvisor scrape profile (TA-selected) **or** document the scope boundary explicitly |
| M11 | Flux GitRepository examples track `branch: main` with no tag/commit/cosign verification | `examples/flux/*/source.yaml` | Show `ref.tag` pinning + `spec.verify` (GPG) in at least one example; document `branch: main` as dev/e2e only |
| M12 | Prometheus Operator CRDs fetched from `raw.githubusercontent.com` at a (mutable) tag with no checksum | `Makefile:22-23,91-92` | Vendor the pinned CRDs into the repo and apply from disk, or record + verify their sha256 (also makes e2e reproducible offline) |
| M13 | OTel collector image has no explicit tag/digest — it floats with chart appVersion, which itself floats via `0.147.x` | `base/otel-collector/values.yaml:1-2` | Set `image.tag` (matching the pinned chart appVersion) and ideally `image.digest` |

## 6. Low-Severity Findings

- **L1 · In-memory sending queues** *(corrected from High).* ADR-0009 explicitly
  promises *bounded*, not durable, buffering, and `docs/architecture.md` already
  says telemetry "can wait in memory." So this is **not a defect** — but the
  restart-loss consequence (OOM/eviction/upgrade drops the queue) should be
  made first-class next to the buffering diagram, with an opt-in `file_storage`
  durable-queue recipe for clusters that want it. Do not enable durable queues
  in `base/` (conflicts with ADR-0009's preference for predictable resource use;
  each replica would need its own volume).
- **L2 · Self-monitoring not wired by default** *(corrected from High).* The
  collector exposes its own metrics on `:8888`, but nothing in-repo scrapes
  them — **by documented design** (external Prometheus opt-in via disabled
  ServiceMonitor hooks). Improve discoverability: link the disabled hooks to the
  specific signals ADR-0009 names (`otelcol_exporter_send_failed_*`,
  `otelcol_exporter_queue_size`, `otelcol_processor_dropped/refused`,
  memory_limiter). Optionally ship a self-monitoring profile that enables the
  hooks **and** labels them `telemetry.example.com/scrape: "true"` so the
  in-overlay Target Allocator discovers them. Note: routing self-metrics through
  the gateway's own pipeline means they can be dropped during the very upstream
  outage you want to observe — the external-Prometheus path is more robust.
- **L3 · Label divergence.** `examples/flux/prometheus-crds/target-allocator-cluster-values.yaml:19`
  overrides the selector to `observability.example.com/scrape=enabled`,
  diverging from the repo's own `telemetry.example.com/scrape=true`. Copy-pasted
  with bundle profiles, it discovers nothing. Show it as a *commented*
  alternative, or keep the bundle-default label.
- **L4** `metrics/from_logs` omits `memory_limiter` while every other pipeline
  includes it (`base/otel-collector/values.yaml:188`).
- **L5** Target Allocator single-replica, no PDB — acceptable (existing scrapes
  continue during TA downtime; only rebalancing pauses); document the behavior.
- **L6** `.gitignore` ignored `AGENTS.md` and `docs/agents/`; in this checkout
  those files were ignored/untracked, not committed. Un-ignore the files that
  describe repo agent behavior, or remove the scaffolding if it is intentionally
  local-only.
- **L7** Hand-maintained `vm-query` Service selector can silently break if a VM
  chart upgrade changes pod labels — add an e2e assertion that
  `kubectl get endpoints vm-query` has ≥1 address.
- **L8** HelmRelease `interval: 1h` ⇒ up to ~1h self-heal latency for a wedged
  release; consider 5–10m for critical releases.
- **L9** No NetworkPolicy for the open OTLP receivers (`0.0.0.0:4317/4318`); any
  pod can push telemetry. Cilium is already an e2e dependency — a
  CiliumNetworkPolicy profile is natural.
- **L10** Fluent Bit → collector is plaintext (`Tls Off`) with
  `Log_response_payload True`; acceptable in-cluster but worth noting (recommend
  Cilium transparent encryption; `Log_response_payload False` outside debugging).

## 7. Verified Non-Issues (Do Not "Fix")

These were flagged by one or more review lenses and **overturned** by adversarial
verification against actual runtime behavior. Changing them would add risk.

- **`OTEL_K8S_POD_NAME` "never injected."** The collector chart `0.147.2` (the
  highest match for the `0.147.x` pin) injects `OTEL_K8S_POD_NAME` from
  `fieldRef: metadata.name` **unconditionally** in its pod template, so
  `collector_id` is unique per replica and Target Allocator sharding works. The
  *only* residual risk is the floating `.x` range, which could resolve to
  `0.147.0` (which lacks it). Handled by H3 exact-pinning; optionally also set
  the env explicitly via Downward API to make the manifest self-documenting.
- **`collector_selector: matchlabels:` (lowercase) "selects nothing."**
  The Target Allocator's `MapToLabelSelector` decode hook yaml-marshals the
  sub-map and matches the lowercased Go field name, so `matchlabels` is the
  natively-correct key; the hook even converts camelCase `matchLabels` **down**
  to `matchlabels` (PR #3418). The deployed chart (`0.127.x` → TA app ~0.150)
  accepts both. Upstream issue #3350 is the **reverse** failure. Optionally
  align casing for in-file consistency, but **do not** add a static check that
  rejects lowercase `matchlabels:` — that rule is backwards and would push
  toward the form that broke on older Target Allocator versions.

## 8. Strengths (Do Not Regress)

- **Processor ordering is correct in every pipeline:** `memory_limiter` first,
  `batch` last, `tail_sampling` after `resource/cluster`.
- **`transform/scrub` is sequenced so its `keep_keys` allowlists preserve
  exactly the attributes the `count` connector reads** (`http.method`,
  `http.route`, `http.response.status_code`) — an easy thing to break, gotten
  right.
- **The `metrics/prometheus-crds` pipeline deliberately bypasses the scrub
  allowlist** so Prometheus label sets survive — a thoughtful, non-obvious
  correctness detail.
- **VictoriaMetrics OTLP sink is correct** (`/opentelemetry/v1/metrics:8428` +
  `usePrometheusNaming`); `dependsOn` ordering is coherent; `valuesFrom`
  discipline is clean (no inline `spec.values`); the `vm-query` selector matches
  the chart's real pod labels; all eight kustomize entrypoints render.
- **ADR discipline, glossary, ownership boundary, and the profile model** are a
  real asset — the bundle owns the data plane and correctly disclaims canary,
  KEDA, dashboards, and auth.
- **The Cilium-backed Kind e2e** (kube-proxy replacement, Hubble, host
  preflight, diagnostics collector) is an ambitious, genuine integration test
  for a manifest-only repo, with CLIs exactly pinned via aqua.
- **No credentials shipped**; upstream TLS verification on by default; sound
  secret-manager-agnostic auth pattern in `docs/secrets.md`.

## 9. Refactors

1. **Two-tier collector for traces (H1).** Stateless ingest tier
   (`loadbalancing` exporter, `routing_key: traceID`, headless Service) → a
   dedicated tail-sampling tier. The ingest tier must not run `tail_sampling`.
   *Effort: L.*
2. **Split the scrape collector from the ingest collector (M7).** A dedicated
   StatefulSet collector fed by the Target Allocator, with stable identity for
   consistent-hashing rebalance, separate from the OTLP ingest Deployment.
   *Effort: M.*
3. **Pod Security boundary split (M1).** Harden the collector's `securityContext`
   regardless of namespace policy; move only Fluent Bit + node-exporter into a
   dedicated privileged namespace; keep `telemetry` at `baseline`/`restricted`.
   *Effort: M.*
4. **Optional durable-queue overlay (L1).** A `file_storage`-backed sending
   queue on a per-pod volume (StatefulSet) as an opt-in profile — not in `base/`.
   *Effort: M.*

## 10. Future Features / Roadmap

Sequenced to protect the design strengths (lean base, profile model, ownership
boundary) while closing correctness, scale, and supply-chain gaps.

```text
P0 — correctness & safety
  1. Two-tier collector for correct tail sampling .................... L
  2. deltatocumulative + Fluent Bit attribute coercion for
     http_5xx_errors_total ......................................... S/M
  3. CI: kubeconform + otelcol validate + flux build + Renovate +
     exact-pin charts .............................................. S
  4. Fail-fast CLUSTER sentinel + render assertion .................. S
  5. PDBs + topologySpread for collector and VM .................... S

P1 — resilience & scale
  6. Dedicated StatefulSet scrape collector (split from ingest) ..... M
  7. Self-monitoring profile + starter PrometheusRule (exporter
     failed, queue near full, dropped/refused, VM down, FB retries) . S/M
  8. cosign/OCIRepository verify; optional file_storage queue ....... S/M

P2 — parity & features
  9. presentation profile: Grafana JSON + PrometheusRule + KEDA
     ScaledObject keyed on `cluster` ............................... M
 10. kubelet/cAdvisor/apiserver scrape profile (or document scope) .. M
 11. NetworkPolicy/CiliumNetworkPolicy profile for OTLP ingress ..... S
 12. VictoriaMetrics persistence option / optional vmagent .......... M
 13. LICENSE, SECURITY.md, CONTRIBUTING, CODEOWNERS ................. S
```

## 11. Implementation Plan

A suggested, low-risk sequence. Each step is independently shippable and should
be done on a branch with the new CI checks (step 0) gating it.

### Phase 0 — Make change safe (do first)
- Add `.github/workflows/ci.yml`: install aqua → `make manifests-check` piped
  through kubeconform (strict, Flux schemas) → `otelcol validate` on the
  rendered collector config → `flux build`/`helm template` → `yamllint`.
- Add `renovate.json` (or `.github/dependabot.yml`) for the OCI chart versions,
  aqua tool versions, the Cilium version, and the Prometheus Operator CRD tag.
- Pin every chart to an exact version (`0.147.x` → `0.147.2`, etc.).
- Add `LICENSE` and `CODEOWNERS`.

### Phase 1 — Correctness
- **Traces (H1):** introduce the two-tier collector (or, as an interim, a
  single-replica trace tier). Add a `check-e2e-kind.sh` assertion that
  `tail_sampling` is never paired with `replicaCount > 1` without trace-ID
  routing. Add an ADR.
- **Derived metric (H2):** add `deltatocumulative` to `metrics/from_logs` before
  the VM exporter; add a `transform` to coerce the Fluent Bit log field into a
  numeric `http.response.status_code`; add an e2e assertion that a synthetic 5xx
  log produces a non-empty series in VictoriaMetrics. Correct the docs.
- **Identity (M2):** replace the `base-cluster` default with a fail-fast
  sentinel + a render assertion.

### Phase 2 — Reliability & hardening
- PDBs + `topologySpreadConstraints` for the collector; PDB for VM (H5).
- Hardened collector `securityContext`; plan the Pod Security namespace split
  (M1). Narrow Fluent Bit tolerations and host mounts (M3).
- Self-monitoring profile + starter `PrometheusRule` (L2); upstream-outage
  runbook keyed to concrete signals/thresholds.
- Tune collector CPU limit and `memory_limiter` absolute bounds (M5); decide the
  Fluent Bit retry/pause tradeoff (M6).

### Phase 3 — Supply chain & integrity
- Migrate OCI sources to `OCIRepository` + `chartRef` with `spec.verify` cosign
  (verify chart-artifact signing per publisher first) (H3).
- Pin the collector image tag/digest (M13); vendor or checksum the Prometheus
  Operator CRDs (M12); show pinned `ref.tag` + GPG verify in a Flux example
  (M11).

### Phase 4 — Parity & presentation
- `presentation` profile (dashboards, rules, KEDA example) as examples-first
  (M9).
- kubelet/cAdvisor/apiserver scrape profile or an explicit scope note (M10).
- NetworkPolicy/CiliumNetworkPolicy profile (L9); optional StatefulSet scrape
  collector (M7); optional durable-queue and VM-persistence overlays (L1).
- Reconcile the contradictory Flux deploy guidance and the gitignored agent
  scaffolding (M8, L6).

---

## Appendix A. Finding Index

| ID | Severity | Category | Title |
|----|----------|----------|-------|
| H1 | High | bug | tail_sampling incorrect at replicaCount 3 (no trace-ID routing) |
| H2 | Medium | reliability | http_5xx_errors_total depends on unverified Fluent Bit status-code attributes |
| H3 | High | security | floating `.x` chart pins + 1h re-poll, no review/integrity gate |
| H4 | High | reliability | no CI; render-only validation (no schema/otel/flux checks) |
| H5 | High | reliability | no PDB/topologySpread/anti-affinity; VM single replica |
| M1 | Medium | security | collector lacked explicit hardening under namespace-wide privileged PSS |
| M2 | Medium | reliability | silent `CLUSTER=base-cluster` default mislabels/collides |
| M3 | Medium | security | Fluent Bit tolerates all taints (control-plane logs) + writable hostPath |
| M4 | Medium | performance | count connector `http.route` cardinality; no consumer guidance |
| M5 | Medium | performance | collector CPU 250m throttling; tight memory_limiter headroom |
| M6 | Medium | reliability | Fluent Bit Retry_Limit 5 + pause = log-loss tradeoff |
| M7 | Medium | performance | single-tier collector also does TA scraping |
| M8 | Medium | docs | contradictory Flux deploy guidance (overlay README vs top-level) |
| M9 | Medium | future-feature | presentation profile promised but absent |
| M10 | Medium | future-feature | no kubelet/cAdvisor/apiserver scraping vs parity claim |
| M11 | Medium | security | Flux GitRepository examples track branch:main, unverified |
| M12 | Medium | security | Prom-operator CRDs from raw URL, no checksum |
| M13 | Medium | security | collector image no explicit tag/digest |
| L1 | Low | reliability | in-memory sending queues (documented; clarify + opt-in durable) |
| L2 | Low | reliability | self-monitoring not wired by default (documented external opt-in) |
| L3 | Low | dx | flux prometheus-crds example label divergence |
| L4 | Low | reliability | metrics/from_logs missing memory_limiter |
| L5 | Low | reliability | Target Allocator single-replica, no PDB |
| L6 | Low | dx | gitignored AGENTS.md/docs/agents committed; reference missing tracker |
| L7 | Low | reliability | vm-query custom Service selector fragility |
| L8 | Low | reliability | HelmRelease 1h interval self-heal latency |
| L9 | Low | security | no NetworkPolicy for OTLP receivers |
| L10 | Low | security | Fluent Bit plaintext + Log_response_payload True |
| — | Non-issue | — | OTEL_K8S_POD_NAME (works on pinned chart; latent version risk only) |
| — | Non-issue | — | collector_selector `matchlabels` casing (functionally correct) |
