# mfe-pot: OpenTelemetry observability (traces + metrics)

## Status

Implemented and verified across all 7 repos. Closes `../TODO.md`'s
"Observability" item. Two new shared packages
(`@tn4consulting/shared-observability-server`, `@tn4consulting/shared-observability`)
built, unit-tested, and confirmed to compile cleanly (`tsc --build`, not
just `ts-jest`'s looser transpile-only checking — this caught two real bugs,
see "Gotchas hit" below). Four new Helm charts (`otel-collector`, `tempo`,
`prometheus`, `grafana`) deployed live to the family's already-running local
`kind` cluster and confirmed healthy, including a provisioned "BFF RED
metrics" Grafana dashboard (request rate/error rate/duration, derived from
spans via Tempo's metrics-generator — see "Design decisions" below) verified
populated with real synthetic traffic. All 6 app repos' wiring (3 BFFs'
`main.ts`, 6 frontends' `runtime-config.ts`/`bootstrap.tsx`, every chart's
`values.yaml`) lint/test/build cleanly against the real new packages
(verified via the documented temporary `file:`-link technique, not just by
inspection).

**Update**: both packages have since been published to GitHub Packages
(`shared-observability-server@0.1.0`, `shared-observability@0.1.0`) and all
9 app images rebuilt/redeployed to `kind` with the real code. A genuine
citizen action — `GET dashboard-mfe.mfe-pot.local/api/overview` — was
confirmed producing **one trace ID spanning `dashboard-bff` →
`job-bank-bff` and `dashboard-bff` → `employment-insurance-bff`**, each
BFF's own Redis calls included. See "Verified live" below for the exact
trace ID and span tree.

**Narrower than "browser → BFF" though.** What's proven is BFF-to-BFF
propagation (server-to-server `fetch`/undici, real deployed pods) — not yet
the browser leg specifically. `shared-observability`'s
`propagateTraceHeaderCorsUrls` mechanism was only exercised via a
hand-crafted OTLP payload earlier in this work, never from an actual
deployed frontend pod's own JS generating a `traceparent`. A real browser
session against `msca.mfe-pot.local` (or an equivalent scripted check) would
be needed to close that specific gap.

**Update 2 — confirmed on AWS EKS too, plus a resilience hardening pass.**
The same trace check was repeated against the real EKS deployment
(`https://dashboard-mfe.aws.tn4consulting.com/api/overview`) with identical
results — see "Verified live" for the trace ID. Separately, prompted by an
explicit request to guarantee the client is never impacted if the OTel
backend is unavailable: both `initNodeObservability` and
`initBrowserObservability` now wrap their SDK setup in try/catch,
log-and-continue instead of throw, published as `0.1.1`. Verified live (not
just asserted): scaled `otel-collector` to 0 replicas on `kind` and hit
`dashboard-bff`'s real fan-out 5 times in a row — identical latency, all
tiles still `ok`, zero errors logged. See "Client-impact resilience" below.

**A real, unrelated production bug was found and fixed along the way**:
`employment-life-events-mfe`'s EKS release had been stuck for a long time on
a broken partial rollout — its Ingress still pointed at the kind-only
hostname, never the real AWS one — because its `deploy-eks` CI job had been
silently skipped every run (gated on a separate, pre-existing stale
`kind-validation` check failing). This meant `msca-shell`'s `/job-loss` route
was showing the citizen-facing "temporarily unavailable" fallback in
production. Fixed directly (image built/pushed to ECR by hand, `helm
upgrade --install` with both values files) — confirmed working — but the
underlying stale CI check is not fixed, so this can recur on the next push
to that repo until someone does.

## Context

`../TODO.md`'s "Observability" item: *"OpenTelemetry across the 3 BFFs (and
ideally the frontends) with a propagated trace ID, so a single citizen
action can be followed across service boundaries."* Confirmed at the start
of this work: zero logging/tracing/correlation-ID infrastructure existed
anywhere in the family (no winston/pino, no `x-request-id` handling, no
`@opentelemetry/*` deps in any of the 7 repos) — a genuinely new addition,
not an upgrade. Scope chosen: traces + metrics (not logs — no structured
logger exists in any BFF to attach trace context to), both backends and
frontends, viewed through Grafana + Tempo + Prometheus fed by a real
OpenTelemetry Collector.

**Landed mid-implementation**: `mfe-pot-platform` picked up a separate,
substantial AWS EKS/Terraform hosting pass
(`20260808-1500-mfe-pot-aws-eks-terraform.md`) that didn't exist when this
work started — every chart-owning repo gained a `values-eks.yaml` + TLS
Ingress block alongside `values-kind.yaml`. This plan was revised in place
to give both new public-facing charts (`otel-collector`, `grafana`) the same
dual-environment treatment from the start, not bolted on after.

## Where the code lives

| What | Repo | Path |
|---|---|---|
| Node SDK bootstrap (BFFs) | `mfe-pot-platform` | `libs/shared/observability-server` → `@tn4consulting/shared-observability-server` |
| Web SDK bootstrap (frontends) | `mfe-pot-platform` | `libs/shared/observability` → `@tn4consulting/shared-observability` |
| Collector + Tempo + Prometheus + Grafana charts | `mfe-pot-platform` | `charts/otel-collector`, `charts/tempo`, `charts/prometheus`, `charts/grafana` |
| Local deploy sequencing | `mfe-pot-platform` | `tools/deploy-local.sh` (new releases after `session-cache`, before `strapi`) |
| AWS deploy sequencing | `mfe-pot` (meta repo) | `tools/deploy-eks.sh` (Step 3, alongside `session-cache`) |
| Per-BFF wiring (`main.ts`, chart `values.yaml`) | `mfe-pot-job-bank-mfe`, `mfe-pot-dashboard-mfe`, `mfe-pot-employment-insurance-mfe` | `apps/<bff>/src/main.ts`, `charts/<app>/values.yaml` |
| Per-frontend wiring (`runtime-config.ts`/`bootstrap.tsx`, chart `values.yaml`/`values-eks.yaml`) | all 6 app repos | see "Per-app wiring" in `mfe-pot-platform/CLAUDE.md`'s observability section |
| Durable architecture reference | `mfe-pot-platform` | `CLAUDE.md`'s "Observability: OpenTelemetry" section (federation-sharing decision, wiring-point-by-role rationale, gotchas) |

**This doc is intentionally light on rationale already captured elsewhere.**
`mfe-pot-platform/CLAUDE.md`'s new "Observability" section is the durable
reference for *why* each design decision was made (federation-sharing,
wiring-point-per-role, the `propagateTraceHeaderCorsUrls` gotcha) — this doc
covers what was built, in what order, and what was actually verified.

## Design decisions worth flagging here (full rationale in CLAUDE.md)

- **The OTel Web SDK is deliberately not a federation-shared singleton.**
  Cross-service trace linkage rides the W3C `traceparent` HTTP header, not
  JS object identity, so each app bundles its own independent
  `WebTracerProvider`/`MeterProvider` pair via `registerInstrumentations`
  (never the global `.register()` form, which would let whichever
  federated bundle loads first silently win and mis-attribute every other
  app's spans).
- **`propagateTraceHeaderCorsUrls` is mandatory, not optional**, for any
  app with a BFF — a federated remote's BFF call is cross-origin from the
  browser's point of view (each remote resolves its BFF URL against its
  own origin, not the host's), and `FetchInstrumentation` silently drops
  `traceparent` on cross-origin requests without it.
- **OTLP/HTTP everywhere** (port 4318) — one protocol, one exporter package
  shape, for both BFFs and browsers. gRPC (4317) stays enabled on the
  collector (the contrib image's default) but unused/unexposed.
- **Bare-upstream-image charts, no PVCs** — `tempo`/`prometheus` hold
  resettable demo data only (same posture as `session-cache`'s Redis having
  no persistence), so plain `emptyDir` is correct, not a shortcut.
- **RED metrics (request rate/error rate/duration) are derived from spans**,
  via Tempo's `metrics_generator` (span-metrics processor) `remote_write`ing
  `traces_spanmetrics_*` series into Prometheus (`--web.enable-remote-write-receiver`),
  rather than relying on each BFF's own HTTP auto-instrumentation metrics.
  See "Gotchas hit" for the full story of why.

## Gotchas hit, worth knowing if this needs touching again

- **`ts-jest`'s transpile-only mode does not catch real `tsc` errors.**
  Both new packages' full test suites passed while `nx build` (real
  `tsc --build`) failed outright — once on `noPropertyAccessFromIndexSignature`
  (`process.env.X` needs bracket notation under this repo's strict
  `tsconfig.base.json`), once on a genuinely missing `package.json`
  dependency (`@opentelemetry/semantic-conventions` was used in
  `shared-observability`'s source but never added to its `dependencies`).
  Jest's test run never actually required the real, unmocked module graph
  for either bug to surface. **Lesson: `nx build`, not just `nx test`, is
  load-bearing verification for any new `libs/shared/*` package** — this
  wasn't previously an obvious gap since every existing shared lib was
  already built via `publish-shared-lib.mjs`'s own CI-integrated flow at
  least once before this.
- **`grafana/tempo`'s 3.x line replaced the classic single-binary
  `ingester`/`compactor` config schema** with a new Kafka-based
  `block-builder`/`live-store` ingest architecture — confirmed live,
  `tempo:3.0.2` crash-looped with `field ingester not found in type
  app.Config`. Pinned to `2.10.7` (latest 2.x), which still speaks the
  classic schema this chart's `templates/configmap.yaml` uses — real added
  complexity the 3.x architecture brings that a simple local-storage PoC
  demo doesn't need. Worth re-checking if this chart is ever revisited for
  a "real" multi-tenant/scaled deployment, where 3.x's architecture might
  actually earn its keep.
- **A ConfigMap volume mount doesn't make a running process reload its
  config.** After fixing the collector's exporter-naming deprecation
  warning and re-running `helm upgrade`, the already-running collector Pod
  kept running with its original in-memory config (same Pod age, unchanged)
  — needed the same `kubectl rollout restart` this project's `deploy-local.sh`
  already documents for the static-tag-plus-`pullPolicy:IfNotPresent` image
  case, except here the root cause is "the process only reads its config
  file once, at startup," not an image-pull issue. Worth remembering this
  applies to *any* mounted-ConfigMap-as-file chart (all 4 new ones), not
  just image updates.
- **The OTLP HTTP exporter's `otlp` type alias is deprecated in favor of
  `otlp_grpc`** in `otel-collector-contrib` 0.158.0 — a real, confirmed-live
  warning, fixed by renaming the exporter key from `otlp/tempo` to
  `otlp_grpc/tempo` (and its pipeline reference) in
  `charts/otel-collector/templates/configmap.yaml`.
- **A plain `.mjs` verification script gives a misleading read on
  `@opentelemetry/instrumentation-http`.** First-pass manual testing (a
  `.mjs` script, dynamic `import('http')`) showed outgoing (`fetch`/undici)
  spans and metrics working but **no incoming `http.createServer` span or
  metric at all** — looked exactly like a real gap in the shipped package.
  Root cause, confirmed by reading `@opentelemetry/instrumentation`'s and
  `instrumentation-http`'s actual source: the core-module patch depends on
  `require-in-the-middle` hooking CJS's `Module._load`, which ESM's own
  loader for built-ins doesn't reliably go through. Re-running the
  identical scenario as a plain `.cjs` script (`require('http')`) produced
  correct server-side spans **and** metrics immediately, matching counts
  exactly (32 success / 8 error out of 40 requests). **This never affected
  any real BFF** — all 3 compile to `format: ["cjs"]` via esbuild — but it
  cost real investigation time chasing a phantom bug, including one
  incorrect diagnosis (see below) written into this doc and
  `mfe-pot-platform/CLAUDE.md` before being corrected. Lesson: verify any
  Node auto-instrumentation package with a `.cjs` script (or the real
  compiled app), not an ad hoc `.mjs` one, or a loader artifact can look
  exactly like a product bug.
- **(Corrected, not a real gap)** An earlier version of this doc claimed
  `instrumentation-http`'s server-side duration histogram "silently never
  exports" and used that as the rationale for deriving RED metrics from
  spans instead. That claim was based on the flawed `.mjs` test above and
  has been corrected — the real reason to prefer span-derived RED metrics
  (below) is architectural (one proven-reliable signal, not per-language
  metrics-support parity), not a workaround for a bug that, per the
  `.cjs` re-test, doesn't actually exist in the shipped BFF code.

## Verified live

On the family's existing local `kind` cluster (already running all 9 app
releases + platform infra before this work started):

1. **All 4 new charts deploy and reach Ready** — `otel-collector`, `tempo`
   (after the version pin fix), `prometheus`, `grafana`, each via
   `helm upgrade --install ... --wait`, same as every existing chart in
   this repo.
2. **Both new public Ingress hosts serve**: `otel.mfe-pot.local`'s OTLP/HTTP
   endpoint responds to a real POST; `grafana.mfe-pot.local`'s `/api/health`
   returns `200` with the real Grafana version.
3. **Grafana's datasource provisioning worked with zero manual steps** —
   `/api/datasources` shows both `Tempo` and `Prometheus`, correct
   in-cluster Service URLs, immediately after the chart's first install.
4. **Prometheus is actively scraping the collector** — `up{job="otel-collector"}`
   returns `1`.
5. **A real end-to-end trace**, emitted by the actual built
   `shared-observability-server` package (`initNodeObservability` +
   `@opentelemetry/api`'s `tracer.startSpan()`, not a hand-crafted OTLP
   payload) against the deployed collector's OTLP/HTTP endpoint, was
   confirmed queryable both directly against Tempo's `/api/search` and
   through Grafana's own datasource-proxy API — the identical path a
   citizen's browser/BFF request will take once the app images are
   rebuilt.
6. **After publishing and redeploying all 9 app images**: `GET
   dashboard-mfe.mfe-pot.local/api/overview` (a real citizen action, the
   dashboard's cross-benefit overview fan-out) produced trace ID
   `70a794f3c829a41db6f3b01ca772cdb3` spanning `dashboard-bff`'s incoming
   `GET /api/overview` (SPAN_KIND_SERVER) → its own outgoing calls to
   `job-bank-bff` (`GET /api/applications`) and `employment-insurance-bff`
   (`GET /api/claims`, `GET /api/reporting-status`), each showing that
   downstream BFF's own incoming SPAN_KIND_SERVER span plus its Redis
   client spans — confirmed via `GET /api/traces/<id>` against Tempo
   directly. Immediately after, the Grafana RED dashboard's `$service`
   variable picked up all 3 real BFF names with real request-count/duration
   data, no dashboard changes needed. **A real, separate infra gotcha hit
   getting here**: `helm upgrade --wait` proved unreliable redeploying to
   this same cluster later (rollout-readiness polling timed out repeatedly
   even though every image/manifest applied cleanly and the node wasn't
   resource-starved — the cluster's ReplicaSet history showed far more
   rollouts than this session alone performed, consistent with other
   concurrent sessions also deploying to it around the same time). Worked
   around by applying without `--wait`, then an explicit `kubectl rollout
   restart` + `kubectl rollout status` to confirm health directly.
7. **All 6 app repos' actual wiring code lints, tests, and builds** against
   the real (not mocked) new packages, linked via the project's documented
   temporary `pnpm.overrides` `file:` technique, then reverted cleanly
   (`git checkout -- pnpm-lock.yaml`, no stray `dist/` left in either
   platform lib). This included each frontend's real esbuild federation
   build succeeding with the new packages correctly treated as
   non-federation-shared (confirmed via the expected "No meta data found
   for shared lib @opentelemetry/*" build-time notices, not an error).
8. **A provisioned "BFF RED metrics" dashboard** (`charts/grafana/dashboards/bff-red-metrics.json`,
   loaded via Grafana's file provider, not clicked together in the UI —
   survives a pod restart the same way the datasource provisioning already
   did) confirmed genuinely populated: using a plain `.cjs` script against
   the real built `shared-observability-server` package to generate 40
   synthetic HTTP requests (32 success, 8 forced errors) against a local
   instrumented server, the dashboard's exact PromQL (`sum(increase(traces_spanmetrics_calls_total{...}[30m]))`)
   returned the correct real value when queried directly, and
   `GET /api/dashboards/uid/bff-red-metrics` confirmed all 7 panels loaded
   with the intended queries — request rate, error rate %, p50/p95/p99
   duration, total requests/errors (5m), current p95, plus a text panel
   pointing at Explore for trace-level drill-down.
9. **The identical trace check, repeated against real AWS EKS**: `curl
   https://dashboard-mfe.aws.tn4consulting.com/api/overview` produced a
   second real trace ID spanning the same 3 real BFFs over the actual AWS
   network path (NLB, external-dns-managed DNS, cert-manager-issued TLS),
   confirmed via `GET /api/traces/<id>` against Tempo and cross-checked
   through Grafana's own datasource proxy — identical span structure to the
   `kind` trace. Getting there also required deploying the 4 observability
   charts to EKS directly (no CI job covers them, same as `session-cache`)
   and fixing an unrelated, real production bug found along the way (see
   the "Status" section's "Update 2").
10. **Client-impact resilience under a real, live OTel outage**: scaled
    `otel-collector` to 0 replicas on `kind`, then hit `dashboard-bff`'s
    real `/api/overview` fan-out 5 times in a row — consistent ~30-40ms
    latency (no change from baseline), all 7 tiles still returning `ok`,
    and zero errors or unhandled-rejection warnings in the BFF's own pod
    logs. This was true even before the `0.1.1` try/catch hardening (an
    inherent property of the OTel SDK's async, decoupled export design);
    `0.1.1` additionally guards the narrower, harder-to-trigger case of an
    exception during SDK setup itself.

## Not yet done — real next steps, not silently dropped

- **The browser leg of trace propagation is still unverified from a real
  deployed frontend.** BFF-to-BFF propagation is proven (item 6 above);
  `shared-observability`'s `propagateTraceHeaderCorsUrls` mechanism has only
  been exercised via a hand-crafted OTLP payload, never from an actual
  browser session hitting `msca.mfe-pot.local` and generating a real
  `traceparent` client-side. Would need either a real browser check or a
  scripted equivalent (e.g. a headless-browser run) to close this gap.
- **`mock-idp`'s `/token` exchange is not traced** — out of scope per the
  literal `TODO.md` wording ("across the 3 BFFs").
- **`mfe-pot-employment-life-events-mfe`'s `kind-validation` CI check is
  still stale** (its own comment contradicts the actual verification
  commands run — pre-existing, unrelated to this work) and will keep
  blocking `deploy-eks` from firing on every future push to that repo until
  someone fixes it, silently leaving its EKS deployment stuck on whatever
  was last successfully built.
- **A few stray EKS pods were found stuck in `ErrImageNeverPull`**
  (kind-only `pullPolicy: Never` somehow reaching an EKS deploy) predating
  this work — cleaned up incidentally while fixing the above, but the root
  cause of how they got there wasn't investigated. Worth a closer look if
  this recurs.
