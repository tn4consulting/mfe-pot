# TODO

Outstanding work across the whole mfe-pot family (all 7 repos). Lives here,
not in any one sibling repo, because most of what's left touches more than
one repo (hosting/CI, naming, docs, demo narrative) and this meta repo is the
one place that sits above all of them. Pulled originally from the "Known gap"
call-outs in `mfe-pot-platform/CLAUDE.md` and the Demo Narrative section of
`docs/plans/mfe-pot-initial-design.md`. Update this alongside
those docs as items land, and prune items here once they're actually done —
don't let this drift into a stale wishlist.

## Ingress hostname scheme: front doors get plain names, remotes get -mfe — done (2026-08)

Following the second-host-app work below, front-door URLs were simplified
to plain brand names (`msca.mfe-pot.local`, `job-bank.mfe-pot.local`) and
every internal federated remote's Ingress host, repo name, Nx project name,
federation identity, Docker image, and Helm chart/release were suffixed
`-mfe` (`mfe-pot-job-bank-mfe`, `mfe-pot-dashboard-mfe`,
`mfe-pot-employment-insurance-mfe`, `mfe-pot-employment-life-events-mfe`) —
specifically so `job-bank-shell`'s front door and the `job-bank` remote it
composes don't read as one hyphen apart. Each BFF and each remote's own
business-domain naming (Nx `scope:*` tags, `libs/data-access`, CMS content
keys, route paths like `/job-bank` within a shell) deliberately stayed
un-suffixed — that's domain/UX identity, not hosting identity, and there
was no collision to disambiguate there. `mock-idp`'s allowlist, Strapi's
remote directory (`REMOTE_*_URL` env vars + seeded `name` fields), and both
shells' `remoteName=`/`remotes` map keys all updated to match. Verified per
repo: `nx run-many -t lint,test,build --all` green and each affected image
builds. Full cross-repo verification — a live `kind` redeploy of all 9
releases — confirmed every hostname serves, every remote's `remoteEntry.json`
reports the renamed federation identity, and both shells' injected
`runtimeConfig.remotes` correctly key by the new names. Redeploying surfaced
two real bugs, both fixed: (1) the 4 renamed remotes' old-named Helm releases
were still on the cluster and blocked the new releases from claiming
already-existing resources with the same names (BFF ConfigMaps, one Ingress)
— fixed by uninstalling the orphaned old releases first; (2) `mfe-pot-platform`'s
own `tools/deploy-local.sh` force-restarts `mock-idp` after a rebuild but was
missing the identical restart for `strapi` — a real, pre-existing gap (not
new from this change) that let a rebuilt-and-loaded image sit unserved
indefinitely, caught because it made Strapi's remote directory silently
serve stale pre-rename data. Both fixes are now in place; Strapi's directory
confirmed showing exactly the 4 renamed entries with no stale duplicates.

## Second host app: mfe-pot-job-bank-shell — done (2026-08)

Proved the Native Federation pattern generalizes to more than one host app,
not just a single shell. `mfe-pot-shell` was renamed to `mfe-pot-msca-shell`
in place (same git history, every internal identifier cascaded — Nx project
name, federation name, PKCE client ID, Docker image tag, Helm chart/
release/Ingress names, CI, deploy scripts), and a new sibling repo,
`mfe-pot-job-bank-shell`, was scaffolded from it as a second, minimal host
composing only the job-bank remote's own `./Component` under Job-Bank
branding — no sidebar nav (one destination, nothing to navigate between),
no cross-remote widget-loader Contexts, distinct identity end to end
(dev port 4205, Ingress host, Helm release, PKCE client ID). Both hosts
share one `mock-idp` (`ALLOWED_REDIRECT_URI_ORIGINS` now lists both
origins) and, for msca-shell, the same 4 remotes as before — behavior
there is otherwise unchanged. Full design doc:
`docs/plans/20260807-1500-second-shell-host-proof-of-concept.md`.
- **What's proven**: the pattern mechanically works for a second,
  independently-branded, independently-deployed host app sharing the
  platform's infra (mock-idp, Strapi, the federation-shared singletons)
  with the original host — new repo, new Helm release, new Ingress host,
  distinct PKCE client, all verified with `nx run-many -t lint,test,build
  --all` green and a live `kind` deployment of both simultaneously.
- **What's not yet proven**: sustained concurrent load against one shared
  `mock-idp`/Strapi from two hosts, or a host composing more than one
  remote while also being a minimal-scope PoC (job-bank-shell deliberately
  stayed single-remote to keep the proof narrow).

## Angular → React migration — done (2026-08)

All 5 frontends converted from Angular to React, one app at a time
(smallest first: `employment-life-events` → `shell` → `employment-insurance`
→ `dashboard`), with Angular removed entirely rather than kept as a
fallback — matching job-bank, which was React from the start and became the
reference pattern every other app's conversion copied. Full plan and
rationale in `docs/plans/20260805-1200-angular-to-react-migration.md`.
Real, hard-won lessons worth knowing if you're debugging something that
smells like a leftover from either era:
- The classic-vs-automatic JSX transform split (`jsxFactory: React.createElement`
  required for anything bundled as a federation-shared/exposed chunk,
  since `react/jsx-runtime` can't resolve once federation-shared) was the
  single hardest-won lesson, hit and fixed independently in shell,
  `shared-federation-runtime`, and every converted remote before it was
  applied proactively everywhere.
- A cross-remote widget-loader Context silently resolving to `undefined`
  (no error, just the "unavailable" fallback rendering forever) has two
  independent possible causes now, not one: the Context provider missing
  above `RemoteRouteHost` in `apps/msca-shell/src/app/routes.tsx`, **or** a
  host's own hand-written `esbuild` entry bundle not marking the Context's
  owning package `external` (found live while verifying dashboard's own
  conversion — see `mfe-pot-msca-shell`'s CLAUDE.md and commit history).
- `mfe-pot-platform`'s `libs/shared/ui-gcds` (the Angular `MscaAppFrame`
  wrapper) and `libs/shared/ui-scds` (the Angular ng-packagr wrapper
  around `ui-scds-core`) were deleted outright once every consumer
  converted — zero consumers left anywhere in the family, confirmed by
  grep across all 6 repos before deleting, not just assumed.
- Old Angular-shaped major versions of `shared-federation-runtime` (0.3.0)
  and `shared-i18n` (0.1.x) stay published on GitHub Packages as
  historical artifacts — nothing currently depends on them, but they
  weren't unpublished/deprecated on the registry itself as part of this
  cleanup (a registry action, more disruptive than a repo change — flagged
  here rather than done unilaterally).

## Hosting / CI (in progress — see `mfe-pot-platform/CLAUDE.md`'s "Hosting: Kubernetes + Helm" section for the full story)

The Docker-image + Helm-chart pattern is proven and validated on `kind` for
all 5 apps already — this is what's left, not a redesign:

- [ ] Phase 2 — rewire `mfe-pot-platform/apps/mfe-e2e`'s `playwright.config.ts`
      `webServer` array: today it starts nothing at all (`client-profile-service`,
      the one thing it used to start, has been removed entirely — its
      payments/correspondence data now lives directly in `dashboard-bff`'s
      own local `data.ts`). Needs each of the 5 sibling app repos' `nx serve`
      pointed at from their checkout paths so the composed suite covers all
      5 apps again.
- [ ] Push `mfe-frontend-lib`/`mfe-backend-lib` (the two Helm library charts,
      in `mfe-pot-platform`) to a registry as OCI artifacts — every app
      repo's `Chart.yaml` still references them via a sibling-checkout-relative
      `file://` path.
- [x] ~~AKS + ACR provisioning~~ — **superseded (2026-08): cloud target
      switched from Azure to AWS EKS**, deliberately (no technical reason —
      the Azure account in question is unmanageable), and this pass uses real
      Terraform IaC rather than the checked-in-CLI-script approach the
      superseded plan recommended. Full design in
      `docs/plans/20260808-1500-mfe-pot-aws-eks-terraform.md`; Terraform lives
      in `mfe-pot-platform/infra/terraform/{bootstrap,foundation,cluster}`
      (written and `terraform validate`d, not yet applied to a real account —
      blocked on working AWS credentials). Also corrects a stale count in the
      old plan: there are **8** public Ingress hosts today, not 5 (mock-idp
      has its own too).
- [ ] Land the per-app-repo half of the above: `values-eks.yaml` + Ingress TLS
      block + a `deploy-eks` CI job in each of the 6 app repos plus
      `mfe-pot-platform`'s `mock-idp`/`strapi` charts, and
      `mfe-pot/tools/deploy-eks.sh` for cross-repo bring-up. See the design
      doc's "Build order" section for the exact sequence.
- [ ] `pnpm demo:reset` — each of the 3 BFFs now has its own `POST
      /api/reset` (backed by `@tn4consulting/shared-session-cache`), but
      there's still no single cross-repo command that calls all 3 (this meta repo has no
      root `package.json` to hang one off), and the BFF pods running on
      `kind` today are still on the old in-memory code, not yet rebuilt
      against the real published `@tn4consulting/shared-session-cache`. A
      small script (a curl loop over the 3 BFFs' URLs) most naturally
      belongs in `mfe-pot-platform`'s `apps/mfe-e2e`, which already
      coordinates all the sibling repos for the composed test suite.
      `mfe-e2e`'s golden-path test still works around the underlying gap
      with loose assertions instead of exact counts in the meantime.
- [ ] `mfe-pot/tools/deploy-local.sh`'s conditional build/deploy (skip a
      sibling repo's build+deploy step when its git tree — HEAD +
      uncommitted/untracked changes — matches what was last successfully
      deployed and its helm release(s) are still up) is hand-rolled bash
      plus a git-diff hash, not a real target-based build system.
      Considered 2026-08-05: a lightweight task runner (`Task`/go-task, or
      `Just`) could replace it with declared `build`/`package`/`deploy`
      targets and proper input/output up-to-date checks — closer to what
      `make` does, but nicer syntax — worth it only if the current bash
      approach starts feeling fragile or grows more special cases.
      Deliberately not reaching for something heavier (Bazel, tying the 6
      repos together via a shared Nx graph) since that cuts against the
      repos' intentional independence (see `mfe-pot-platform/CLAUDE.md`'s
      "Monorepo → per-app repos"). Not blocking anything today — Docker's
      own layer cache already makes the actual image builds cheap when
      unchanged (confirmed: a no-op strapi rebuild is ~1.2s, every layer
      CACHED), so this would only save the surrounding orchestration
      overhead (git pull, `helm upgrade --wait`, ingress polling).
## Stale Firebase-era functionality — resolved (2026-08-06)

Firebase Hosting itself was already retired (`firebase.json`/`.firebaserc`
gone, `mfe-pot-platform/CLAUDE.md`'s "Hosting" section says so). A few things
built specifically to cope with Firebase's constraints (can't run Strapi, so
needed baked-in static fallbacks) were still sitting in the codebase; audited
and closed out:

- [x] `mfe-pot-platform/libs/shared/remote-registry`'s
      `StaticRemoteRegistryProvider` was genuinely dead code — confirmed via
      grep across all 6 repos (at the time), nothing imported `@tn4consulting/shared-remote-registry`
      at all (`mfe-pot-msca-shell/apps/msca-shell/src/main.tsx` inlines its
      own registry logic instead — see `mfe-pot-platform/CLAUDE.md`'s bare-specifier
      gotcha). Deleted the class, its spec, and the export in
      `libs/shared/remote-registry/src/index.ts`; `nx test`/`build` still
      green for the lib.
- [x] `StaticContentClient` (`mfe-pot-platform/libs/shared/content-client`) —
      **kept, not deleted**: confirmed it's genuinely load-bearing today, not
      a Firebase leftover. Every app's own `*.spec.tsx` (`App.spec.tsx` in all
      5 apps, `ReportingStatus.spec.tsx` in employment-insurance) deliberately
      mocks `loadRuntimeConfig` to return `strapiBaseUrl: undefined`
      specifically so content comes from `StaticContentClient`'s baked
      fallback instead of needing a live Strapi or a fetch mock for CMS
      content — required by `mfe-pot-platform/CLAUDE.md`'s "no dependency on
      real external services for tests" rule. Only the class's own doc
      comment (platform repo) still said "Firebase-hosted demo" — reworded to
      describe the actual current reason (test isolation) instead. The 4 app
      repos' own `STATIC_CONTENT` comments turned out to already have been
      reworded away from Firebase phrasing at some earlier point — this
      item's original "Baked fallback for the Firebase-hosted build" quote
      was stale by the time this was picked up.
- [x] `mfe-pot-platform/.claude/settings.local.json`'s dead
      `Bash(firebase deploy *)` allowlist entry removed.
- [ ] Lower priority, cosmetic only, deliberately left as-is:
      `tools/docker/nginx.conf` (same file copied into all 5 frontend-app
      repos) and each repo's `.gitignore` still reference "the old
      firebase.json"/"retired Firebase Hosting" in comments. Accurate
      history, not broken functionality.

## `publish-shared-packages.yml` — now actually working end to end

Fixed a chain of pre-existing bugs that had silently kept this workflow
failing on every run (checked: every run on `main` before this had failed,
several dating back days) — worth knowing since none of these are specific
to `shared-ui-scds`, the change that surfaced them:
- `pnpm/action-setup@v4` had no version pinned (failed immediately at
  setup) — fixed with an explicit `version:` matching `platform-versions.json`.
- Root `pnpm-lock.yaml` was stale relative to a new `libs/shared/*`
  workspace project — a reminder to run `pnpm install` at the repo root
  after adding one, not just inside the new lib's own directory.
- The workflow's default `GITHUB_TOKEN` doesn't reliably get read/write
  access to this org's own private `@tn4consulting/*` packages via each
  package's individually-configured "Manage Actions access" allowlist, even
  once correctly set (confirmed well past any reasonable propagation
  delay) — replaced with a PAT-backed `NPM_READ_TOKEN` repo secret, applied
  job-wide.
- `publish-shared-lib.mjs`'s "already published, no-op" detection
  case-sensitively matched `'cannot publish over'`, but the real registry
  error text is `"Cannot publish over existing version"` (capital C) — so
  the common case (re-running the workflow with no version bump) hard-failed
  instead of no-op'ing. Fixed with a case-insensitive check.

## E2E test architecture (`mfe-pot-platform/apps/mfe-e2e`)

- [ ] Adopt the page object (page class) pattern across the 5 specs
      (`golden-path`, `federation`, `accessibility`, `i18n`,
      `widget-embedding`) to abstract tests from page structure. Today every
      spec calls `page.getByRole/getByText/locator` directly inline, with
      route paths, button labels, and `h1` checks duplicated across files;
      the only existing shared helper is the non-class `signIn(page)`
      function in `support/sign-in.ts`. Independent of the pending Phase 2
      `webServer` rewire above — a pure refactor of specs/helpers in this
      repo.

## Design principles (not yet documented/enforced — captured from a mobile note, needs write-up in `mfe-pot-platform/CLAUDE.md` once agreed)

- [ ] UI apps and libraries may only call their own BFF — they may not call
      other BFFs or backend services directly.
- [ ] BFFs must not call each other, but they may call backend services.
- [ ] The application must be deployable without an outage (zero-downtime
      deploys).
- [ ] The app must survive a failure of any node without client impact.
- [ ] Shared state (session storage) managed cross-application via Redis —
      already in place via `@tn4consulting/shared-session-cache` (see
      `mfe-pot-platform/CLAUDE.md`).
- [ ] A/B testing as a first-class design principle — changes must be
      testable at small scale for impact before full rollout.

## Backend-outage resilience — design only, not started

Design doc: `docs/plans/20260808-1800-backend-outage-resilience.md`. Covers
degraded-read serving (Redis single-pod → primary+replica, per-BFF
last-known-good cache), per-domain business rules for how stale data may be
used, async client-side write queueing for submissions made while the
backend is unreachable (EI application/biweekly report as the proof case),
and health/circuit-breaker signaling to drive UI mode. Recommended proof
scope is `employment-insurance-mfe`/`-bff` only, generalizing later — not
all BFFs/frontends at once.

- [ ] Redis primary+replica (or Sentinel) in `mfe-pot-platform/charts/session-cache`
- [ ] Shared `libs/shared/resilience-server`: circuit-breaker `SessionCache`
      decorator + shared degraded-response envelope
- [ ] Shared `libs/shared/resilience-client`: `useBackendHealth` hook,
      outbox/queue primitive, degraded-mode banner
- [ ] `/health` → real readiness (Redis check) on all 3 BFFs
- [ ] Idempotency-keyed write endpoints, starting with
      `employment-insurance-bff`'s `POST /api/applications` and report submit
- [ ] Demonstrator: `employment-insurance-mfe` read-degraded banners +
      queued submission UI
- [ ] Open decision, not yet made: queue durability (in-tab retry vs.
      Service Worker + Background Sync) — decide when this is picked up

## Demo narrative (proves the point, not just the pattern)

Not started. See `docs/plans/mfe-pot-initial-design.md`'s
"Demo Narrative & Experience" section for the full specifics.

- [ ] Siloed-mode toggle in `mfe-pot-msca-shell` — disables the cross-service calls
      `mfe-pot-employment-life-events-mfe`/`dashboard-bff` normally
      make, so the citizen re-enters details separately and sees three
      disconnected status pages. The "before" picture for the demo.
- [ ] Live "tell us once" demo beat — address/bank details entered once in
      the `mfe-pot-employment-life-events-mfe` journey visibly pre-fill the EI
      application and Job Bank profile. **Needs a redesign before it can be
      built**: this assumed crossing a real shared `client-profile-service`
      boundary reachable by all three domain BFFs, but that service has
      since been removed — its data now lives only inside `dashboard-bff`'s
      own local store (see "Hosting / CI" above), which `job-bank-bff`/
      `employment-insurance-bff` can't reach. A real cross-BFF shared store
      (e.g. the Redis-backed session cache below) would need to exist first.
- [ ] Visible policy-outcome proxy — a journey meter (systems touched, fields
      re-entered, steps remaining, simulated calendar day) fed by both modes:
      siloed mode starts job search ~day 24, life-event mode starts day 1.
- [ ] "Show the seams" overlay — a keypress outlines each federated region on
      screen, labelled with remote name/origin/version read live from
      `RemoteRegistryProvider`.
- [ ] Demo runbook — named persona, timed beats (~5-10 min), and the
      `pnpm demo:reset` command above so the demo can be run live more than
      once.
- [ ] Committed persona/fixture data pack across the BFFs and Strapi —
      plausible Canadian address, ROE, EI amounts/dates, job postings shaped
      like real jobbank.gc.ca listings. French fixtures must be genuinely
      translated, not machine-translated.
- [ ] Bilingual switch demoed as a real flex — triggered mid-EI-application,
      showing form state preserved, CMS content swapped, currency/date
      reformatting (`1 234,56 $`), and the payment-history widget
      re-rendering in French simultaneously inside
      `mfe-pot-employment-life-events-mfe`.
- [ ] Payment-history widget (embedded in `mfe-pot-employment-life-events-mfe`,
      sourced from `mfe-pot-dashboard-mfe`) has its heading/table labels/status
      text CMS-driven and bilingual now (`dashboard.payment-history.*` keys
      — closed alongside the same fix for job-bank's and
      employment-insurance's own feature-level headings/labels, previously
      hardcoded English). Still outstanding, narrower than before: currency
      formatting (`$${amount.toFixed(2)}`, no `Intl.NumberFormat`) and
      date formatting are locale-naive, and the payment *values themselves*
      (benefit names, dates, amounts) are still English-shaped test data —
      a prerequisite for the full bilingual demo beat above.

## Language support

- [ ] Add Cree and Inuktitut (`cr`/`iu`) alongside English/French. Scoped by
      an exploration pass — key points:
      - `SUPPORTED_LOCALES` in `mfe-pot-platform/libs/shared/i18n/src/lib/locale-sync.ts`
        is the single source of truth for the `Locale` type and is
        N-language-ready (just an array) — but several places hand-roll
        their own `'en' | 'fr'` union instead of importing `Locale`, and need
        manual updates: `mfe-pot-platform/libs/shared/content-client`'s
        `ContentClient` interface, `StrapiContentClient`,
        `StaticContentClient`, and `mfe-pot-dashboard-mfe`'s static content
        fallback map (`apps/dashboard-mfe/src/app/App.tsx`). Note: `SUPPORTED_LOCALES`
        now lives in `mfe-pot-platform/libs/shared/locale-sync/src/lib/locale-sync.ts`,
        its own package since the React migration (Phase 0) — not inside
        `shared-i18n` anymore, though `shared-i18n` still re-exports it.
      - Each host's language switcher (`AppFrame.tsx`,
        `mfe-pot-msca-shell/apps/msca-shell/src/app/`) is a strict binary toggle, not
        a picker — needs to become a dropdown/menu for 4 languages. GCDS has
        no built-in multi-language picker to reuse (`gcds-header`'s
        `toggle` slot and `gcds-lang-toggle` are both designed for exactly
        one "other" language).
      - **Hard ceiling**: `@gcds-core/components` (v1.4.0) is officially
        bilingual-only. Its `assignLanguage()` util
        (`dist/collection/utils/utils.js`) collapses any non-`fr*` lang to
        `'en'`, and internal validation-error strings
        (`utils/i18n/validation-errors.js`) are a closed `{en, fr}`
        dictionary with no fallback branch. There is no supported way to get
        GCDS's own internal chrome (form validation messages, built-in ARIA
        text) to render in Cree/Inuktitut without forking/patching upstream
        (`cds-snc/gcds-components`) — check upstream GitHub issues before
        committing to that. App-level `useTranslations`-driven content can
        still switch fully; GCDS's own internal strings can't.
      - 10 new translation files needed (`cr.json`/`iu.json` per app,
        matching the existing `public/assets/i18n/{en,fr}.json` pairs in
        each app repo) — the loader itself is generic and needs no code
        changes once the files exist and `SUPPORTED_LOCALES` is extended.
      - Strapi (`mfe-pot-platform/tools/cms/strapi`): `fr` locale is created
        in `src/index.ts`'s `ensureFrenchLocale()` (idempotent, runs on
        every `bootstrap()`). `cr`/`iu` are valid ISO 639-1 codes Strapi's
        i18n plugin should accept the same way; needs an equivalent
        `ensureCreeLocale`/`ensureInuktitutLocale` (or a generalized loop)
        plus seed-data translations in the same file.
      - Each app's `index.html`'s `<html lang="en">` is static and never
        updated on locale switch — pre-existing gap, worth fixing alongside
        this since it matters more with 4 languages than 2.
      - No `Intl.NumberFormat`/`Intl.DateTimeFormat`/Angular `LOCALE_ID`
        usage exists anywhere yet, so there's no CLDR-formatting assumption
        to fight — a genuine plus, since `cr`/`iu` lack full CLDR data.

## Observability

OpenTelemetry (traces + metrics) across all 3 BFFs and all 6 frontends —
implemented, published, and deployed live to the family's `kind` cluster,
with a real citizen action (`dashboard-bff`'s fan-out) confirmed producing
one trace ID spanning all 3 BFFs. AWS EKS confirmation is the next step, not
yet done as of this writing.
Full design, gotchas hit, and exactly what was/wasn't verified live:
`docs/plans/20260808-1630-opentelemetry-observability.md`;
`mfe-pot-platform/CLAUDE.md`'s new "Observability: OpenTelemetry" section is
the durable architecture reference (federation-sharing decision,
per-app-role wiring point, the `propagateTraceHeaderCorsUrls` gotcha).

- [x] Two new shared packages (`@tn4consulting/shared-observability-server`,
      `@tn4consulting/shared-observability`), four new Helm charts
      (`otel-collector`/`tempo`/`prometheus`/`grafana`, deployed once,
      shared across the family like `session-cache`), and every BFF/frontend
      repo's wiring (`main.ts`/`runtime-config.ts`/`bootstrap.tsx`, every
      chart's `values.yaml` + `values-eks.yaml`) — all landed. `deploy-local.sh`
      and `deploy-eks.sh` both sequence the 4 new releases.
- [x] Live-verified on `kind`: all 4 charts Ready, both new public Ingress
      hosts (`otel`/`grafana`) serving, Grafana's Tempo/Prometheus
      datasources auto-provisioned, Prometheus actively scraping the
      collector, and a real span (emitted by the actual built
      `shared-observability-server` package, not a hand-crafted payload)
      confirmed queryable in Tempo both directly and through Grafana's own
      proxy.
- [x] Provisioned "BFF RED metrics" Grafana dashboard (request rate/error
      rate/p50+p95+p99 duration, per service — `charts/grafana/dashboards/bff-red-metrics.json`,
      loaded via file provisioning so it survives a pod restart, not
      clicked together by hand). Built on Tempo's span-metrics processor
      (RED derived from spans, `remote_write`d into Prometheus) rather than
      each BFF's own HTTP auto-instrumentation metrics — see the plan doc's
      "Gotchas hit" for why (a real ESM-vs-CJS `require-in-the-middle`
      nuance, confirmed to not affect any real BFF, which all compile to
      CJS). Confirmed populated with real synthetic traffic before landing.
- [x] Both packages published to GitHub Packages (`@tn4consulting/shared-observability-server@0.1.0`,
      `@tn4consulting/shared-observability@0.1.0`), all 9 app images rebuilt
      and redeployed to `kind` with the real code. Live-confirmed: a single
      `curl` to `dashboard-mfe.mfe-pot.local/api/overview` produced one
      trace ID spanning `dashboard-bff`'s incoming request → its outgoing
      calls to `job-bank-bff` and `employment-insurance-bff` → each of
      their own request handling and Redis calls — the exact cross-BFF
      scenario this item asked for. The Grafana RED dashboard immediately
      showed real per-BFF request/error/duration data, not synthetic test
      traffic. **Narrower than "browser → BFF" though**: this proved
      BFF-to-BFF propagation (server-to-server `fetch`/undici), not yet the
      browser leg specifically (`shared-observability`'s
      `propagateTraceHeaderCorsUrls` mechanism, exercised only via a
      hand-crafted OTLP payload earlier, never from an actual deployed
      frontend pod's own JS) — a real browser session against
      `msca.mfe-pot.local` would be needed to close that last gap.
      **Real, unrelated infra gotcha hit along the way**: `helm upgrade
      --wait` was unreliable redeploying to this cluster (timed out on
      rollout-readiness polling even though images/manifests applied
      cleanly and the node wasn't resource-starved) — root cause not fully
      isolated, but the cluster's ReplicaSet history showed many more
      rollouts than this session performed, consistent with other
      concurrent sessions also deploying to the same shared cluster around
      the same time. Worked around by applying without `--wait`, then an
      explicit `kubectl rollout restart` + `kubectl rollout status` to
      confirm health directly — same net effect, just sidesteps whatever
      made Helm's own polling flaky.
- [ ] Confirm the same end-to-end trace on the real AWS EKS deployment
      (`docs/plans/20260808-1500-mfe-pot-aws-eks-terraform.md`) — not yet
      done. The `kind` verification above is a local proof; EKS is the
      real target this family is meant to actually run on.

## Nx build performance

- [ ] Set up Nx Remote Cache to share build/test/lint cache across the team
      and CI — https://nx.dev/ci/features/remote-cache. Now relevant per-repo
      (each of the 6 repos has its own Nx workspace since the split) rather
      than once across one big workspace.

## Menu / sidebar nav scope: align with real Service Canada service list

`mfe-pot-msca-shell`'s sidebar nav today only lists destinations for the 4
federated remotes that actually exist (Dashboard, Job Bank, Employment
Insurance, plus the employment-life-events guided journey) — it doesn't
reflect the full set of services a citizen sees on the real "Sign in to your
account to access services for:" list on Canada.ca / MSCA:

- Canadian Dental Care Plan (CDCP)
- Employment Insurance (EI) — covered
- Canada Pension Plan (CPP)
- Canada Pension Plan disability
- Old Age Security (OAS)
- Canada Disability Benefit
- Social Insurance Number (SIN)
- National Student Loans Service Centre (NSLSC)
- Canada Apprentice Loan
- Passport

- [ ] Update the menu to be consistent with the services actually supported
      by Service Canada. Needs a scoping pass first: decide which of the
      above become real (or stub/"coming soon") nav entries in
      `mfe-pot-msca-shell` vs. which stay out of scope for this PoC — most
      have no backing remote/BFF today (only EI is implemented; CPP/OAS/CDCP/
      SIN/etc. would each need their own federated remote or at least a
      placeholder route/CMS entry). Likely pairs with the existing
      Profile/Inbox concept-screen work below rather than being fully
      separate.

## Concept UI screens (from `docs/msca-screenshots/`)

Concept screenshots showing target UI for a fuller MSCA experience. Two files
are duplicates of others (different crop, same content):
`notification-settings.png` ≡ `inbox.png`, `view-my-payments.png` ≡
`dashboard.png` — ignore those two. That leaves 6 distinct concepts:
dashboard, profile, inbox, benefit-application-status,
have-a-representative, omnichannel-support. Dashboard is done; `mfe-pot-msca-shell`
has no local routes beyond the 4 federated remotes; no profile/inbox/
notification UI exists anywhere.

Decided approach: build one vertical slice at a time rather than all 6 at
once.

- [ ] Profile screen (`profile.png`) — My Profile/Preferences/Authorizations/
      Security tabs, personal/contact/family info, sidebar links (Message
      Centre, Payments History, Notifications, Document Centre). Natural
      owner is `mfe-pot-dashboard-mfe` per the "tell us once" profile domain
      boundary.
- [ ] Inbox screen (`inbox.png`) — message list with program/date/has-PDF
      filters. No natural app owner yet identified; likely a new
      `mfe-pot-msca-shell`-level local route (global nav concern) backed by a
      not-yet-built service.
- [ ] Have-a-representative / acting-on-behalf-of flow
      (`have-a-representative.png`) — deferred, needs real design: touches
      session/identity and there's currently only a single mock persona
      (`mfe-pot-platform/libs/shared/auth`'s `createMockSession`). Not a
      UI-only mock — decide properly before building.
- [ ] Omnichannel support modal (`omnichannel-support.png`) — Call us / Chat
      with us / Schedule a call. Net-new, no natural owner yet identified
      (candidate: shared shell-level widget, similar pattern to
      `PAYMENT_HISTORY_WIDGET_LOADER`'s host-mediated cross-remote
      composition if multiple remotes need it).
