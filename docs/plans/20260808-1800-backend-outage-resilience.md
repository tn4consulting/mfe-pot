# mfe-pot: backend-outage resilience

## Status

Design only — not started. No code has changed as part of this doc. Closes
out the design half of `../TODO.md`'s "Design principles" bullets *"The app
must survive a failure of any node without client impact"* and *"Shared
state managed cross-application via Redis — already in place"* — this is the
concrete architecture those principles have been missing, and it also
surfaces that "already in place" so far means *shared*, not *resilient*.

## Context

The ask: keep the app usable as best it can during a backend outage rather
than failing outright. Three related ideas prompted this:

1. Serve a "slave"/replica copy of backend data when the primary path is
   down, rather than erroring.
2. Apply business rules to decide what stale/cached data is safe to use —
   sometimes read-only is the right call, sometimes the data is good enough
   to keep using as-is.
3. Let write operations that can't reach the backend right now (e.g.
   submitting an EI application or a biweekly report) be accepted and
   queued client-side instead of rejected, and sent once the backend is
   reachable again.

An audit (three parallel codebase explorations, one per layer) found this
family currently has essentially no resilience layer to build on:

- Each BFF's only data store is the shared Redis `session-cache`
  (`@tn4consulting/shared-session-cache`) — a **single pod, no HA, no
  persistence**. `mfe-pot-platform/charts/session-cache`'s own
  `deployment.yaml` comments this explicitly: *"a resettable PoT demo cache
  with nothing real behind it... would need both [persistence and auth]
  before any real (non-PoT) deployment."* A pod restart or node failure
  loses every application/claim/job-application currently stored.
- **No retry or circuit-breaker library anywhere** in any of the 7 repos
  (`opossum`/`p-retry`/`cockatiel`/etc. all absent from every `package.json`).
  The one existing precedent is `dashboard-bff`'s `UpstreamResult` pattern
  (`apps/dashboard-bff/src/upstream.ts`) — a 2s `AbortController` timeout
  around its fan-out calls to `job-bank-bff`/`employment-insurance-bff`,
  degrading only the affected dashboard tile rather than failing the whole
  response. This protects BFF→BFF calls only; nothing protects any BFF's
  own call into Redis.
- **No caller anywhere wraps `sessionCache.getJson/setJson/reset` in
  try/catch.** `RedisSessionCache` has no internal retry/backoff either
  (`ioredis` with `lazyConnect: true` and nothing else configured). A Redis
  outage today would surface as an unhandled promise rejection → Express
  5's default error handler → a bare `500` with a stack-trace-shaped body,
  not a deliberate `503`.
- **`/health` in every BFF checks process liveness only** — `res.json({
  status: 'ok' })` unconditionally, never touching Redis. There is
  currently no way to observe "BFF process is up but its data layer is
  degraded" from outside the process.
- **Frontends have no offline/queue pattern at all.** Every remote uses
  plain `fetch` + hand-rolled `useState` loading/error booleans — no React
  Query/SWR, no localStorage/sessionStorage/IndexedDB usage anywhere in
  application code. The EI application wizard
  (`EiApplicationForm.tsx`/`Applications.tsx` in
  `mfe-pot-employment-insurance-mfe`) holds its whole 7-step draft in
  transient React state; a submit failure replaces the entire form with a
  flat `<p role="alert">` and the draft is gone, no retry affordance.
- The closest reusable UI building block is `scds-notice`
  (`@tn4consulting/shared-ui-scds-core`) — a toned, `role="note"` banner
  component, not currently used for status/error/offline messaging anywhere,
  but a reasonable base for one. `RemoteErrorBoundary`
  (`shared-federation-runtime`) is the only other "fail visibly, don't
  crash" precedent, and it's scoped to a whole federated remote failing to
  *load*, a different problem.

## Failure modes to design for

These need different handling, not one blanket "backend is down" flag:

1. **Redis unreachable, BFF process alive.** The common case in this
   architecture, since Redis is the only real dependency each BFF has.
2. **BFF pod/process itself unreachable** (crash, node failure, mid-rollout).
   No amount of BFF-side resilience helps here — this is purely a
   client-side concern (cached last-known-good data, queued writes).
3. **BFF→BFF call fails** (dashboard-bff's fan-out to job-bank-bff/
   employment-insurance-bff). Already partially handled by `UpstreamResult`
   — treat as prior art to extend into the shared envelope below, not
   redesign from scratch.

## Pattern 1 — degraded reads via a backend-side replica

The user's "slave copy" idea maps directly onto the fact that Redis today
has no replica at all. Two layers, addressing different failure modes:

- **Redis primary + replica (or Sentinel)** in
  `mfe-pot-platform/charts/session-cache` — an infra-level change, not
  application code. This is the actual "slave copy of the data... at the
  backend" the user described, and it's what would let a primary-pod
  failure (failure mode 1, the node-loss case) fail over to real data
  instead of losing state outright.
- **A short-TTL in-process read-through cache inside each BFF**, layered on
  top. This is what protects against Redis being *fully* unreachable (not
  just a primary failover blip) — the BFF keeps serving its own
  last-known-good copy of whatever it last read successfully. Deliberately
  not a store of record: it's fine that it's lost on pod restart, since its
  only job is bridging a transient outage, not durability.
- Every read response gets tagged with staleness metadata — generalize
  `dashboard-bff`'s existing `{status: 'ok', data} | {status: 'unavailable'}`
  `UpstreamResult` shape into a shared envelope like `{data, asOf,
  degraded: boolean}`, used consistently by both the BFF→BFF fan-out and
  the new BFF→Redis path.

## Pattern 2 — business rules for stale/degraded data

Not one global "read-only during outage" switch — a per-domain policy,
illustrative here, not final (real thresholds are an implementation-time
decision):

| Action | Policy when data is stale/degraded |
|---|---|
| Dashboard overview tiles | Serve stale-with-banner (already close to this via `UpstreamResult`) |
| View existing EI claim / reporting status | Serve stale-with-banner |
| Start a new EI claim | Block, or route through the write-queue (Pattern 3) — starting a claim against possibly-stale eligibility data is the case worth being conservative about |
| Submit a biweekly report | Route through the write-queue — time-sensitive, must still be acceptable even if the backend is down right now |

## Pattern 3 — async/queued writes

Client-side outbox: a submit writes a locally-persisted pending entry
(client-generated idempotency key) *before* attempting the network call,
shows the user a "submission received, will complete once reconnected"
state instead of blocking or failing, and retries with backoff. Requires
BFF write endpoints (e.g. `POST /api/applications`) to accept and dedupe on
that idempotency key — none currently do; today a retried submission would
create a duplicate.

Two sub-decisions this doc deliberately leaves open, to be made when the
work is picked up rather than now:

- **Queue durability** — in-tab retry/localStorage (simpler, matches this
  stack's current lack of a service worker anywhere) vs. Service Worker +
  Background Sync (survives tab close, a materially bigger lift, nothing
  like it exists in the family today). Both are legitimate; which one's
  worth building depends on how strong the "survives tab close" requirement
  actually needs to be for the demo.
- **Reload rendering** — how a queued-but-not-yet-confirmed submission
  should render if the user reloads the page while it's still pending.

## Pattern 4 — health/circuit-breaker signaling

- Extend `/health` to a real readiness check (ping Redis, not just process
  liveness) so "BFF fully down" vs. "BFF up, data layer degraded" becomes
  observable from outside the process — currently indistinguishable.
- Wrap `SessionCache` calls in a small circuit breaker (open after N
  consecutive failures, half-open retry) so a dead Redis fails fast instead
  of every request hanging on connection timeouts. This also becomes the
  thing `/health`'s readiness check reads from.
- Client-side: a shared `useBackendHealth`-style hook polling each BFF's
  `/health`, feeding page-level decisions about whether to allow live
  writes, offer the queue, or go fully read-only.

## Where new code would live (prospective — nothing built yet)

| What | Repo | Path |
|---|---|---|
| Circuit-breaker-wrapped `SessionCache` decorator, shared degraded-response envelope | `mfe-pot-platform` | new `libs/shared/resilience-server` (or extend `session-cache`) |
| `useBackendHealth` hook, outbox/queue primitive, degraded-mode banner (wraps existing `scds-notice`) | `mfe-pot-platform` | new `libs/shared/resilience-client` |
| Redis primary+replica / Sentinel | `mfe-pot-platform` | `charts/session-cache` |
| Per-BFF wiring (`/health` readiness, idempotency-keyed write endpoints) | `mfe-pot-job-bank-mfe`, `mfe-pot-dashboard-mfe`, `mfe-pot-employment-insurance-mfe` | each `apps/<bff>-bff/src/` |
| Demonstrator UI (read-degraded banners + queued biweekly-report/application submit) | `mfe-pot-employment-insurance-mfe` | `apps/employment-insurance-mfe/src/app/` |

## Recommended proof-of-concept scope, when picked up

Don't roll this out to all 4 BFFs / 6 frontends at once. Build the two new
shared libs, then prove the whole pattern end-to-end in
`employment-insurance-mfe`/`-bff` only — it already has both a read path
(Claims, ReportingStatus) and two write paths (application submission,
biweekly report — the report is a genuinely time-sensitive "must still be
acceptable if the backend is down" case, the clearest possible demo of
Pattern 3). This mirrors the family's existing prove-then-generalize
precedent: `mfe-pot-job-bank-shell` was built as a minimal single-remote
proof of the federation pattern before anything generalized to a second
host (`docs/plans/20260807-1500-second-shell-host-proof-of-concept.md`).
Generalizing to the other BFFs/frontends is future work once the pattern is
validated once, live — not part of this pass.

## Open decisions, explicitly not resolved here

- Queue durability: in-tab retry vs. Service Worker + Background Sync.
- Redis HA mechanism: simple primary/replica vs. Sentinel vs. a managed
  service, if this ever moves off `kind`.
- Exact per-domain staleness thresholds/policy — the Pattern 2 table is
  illustrative, not final.
