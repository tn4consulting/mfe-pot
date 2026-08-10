# TODO

Outstanding work across the whole mfe-pot family (all 7 repos). Lives here,
not in any one sibling repo, because most of what's left touches more than
one repo (hosting/CI, naming, docs, demo narrative) and this meta repo is the
one place that sits above all of them. Pulled originally from the "Known gap"
call-outs in `mfe-pot-platform/CLAUDE.md` and the Demo Narrative section of
`docs/plans/mfe-pot-initial-design.md`. Update this alongside
those docs as items land, and prune items here once they're actually done —
don't let this drift into a stale wishlist.

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
- [ ] Land the per-app-repo half of the above: `values-eks.yaml` + Ingress TLS
      block + a `deploy-eks` CI job in each of the 6 app repos plus
      `mfe-pot-platform`'s `mock-idp`/`strapi` charts, and
      `mfe-pot/tools/deploy-eks.sh` for cross-repo bring-up. See the design
      doc's "Build order" section for the exact sequence.
- [ ] `pnpm demo:reset` — each of the 3 BFFs now has its own `POST
      /api/reset` (backed by `@tn4consulting/shared-session-cache`), but
      there's still no single cross-repo command that calls all 3 (this meta repo has no
      root `package.json` to hang one off). The BFF pods running on `kind`
      are now genuinely on the real published `@tn4consulting/shared-
      session-cache` (rebuilt/redeployed and persistence-proved as part of
      the "Design principles" work) — that part of this item is
      resolved; the missing single cross-repo reset command is what's
      still open. A small script (a curl loop over the 3 BFFs' URLs) most naturally
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
gone, `mfe-pot-platform/CLAUDE.md`'s "Hosting" section says so). Audit closed
out everything except one deliberately-left cosmetic item:

- [ ] Lower priority, cosmetic only, deliberately left as-is:
      `tools/docker/nginx.conf` (same file copied into all 5 frontend-app
      repos) and each repo's `.gitignore` still reference "the old
      firebase.json"/"retired Firebase Hosting" in comments. Accurate
      history, not broken functionality.

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

## Scaling to multi-team ownership (in progress — see `docs/plans/20260808-1200-multi-team-scale-governance.md` for the full design)

Prompted by moving to one team per repo (7 teams; `mfe-pot-platform` as the
platform/DX team). Strong *technical* contracts already exist
(`platform-versions.json`, published `@tn4consulting/shared-*` packages,
module-boundary enforcement, per-repo CI, a shared Renovate preset) but
there's been zero coordination/governance tooling — see the design doc for
the full survey. `@tn4consulting/shared-platform-standards` (drift check,
synced `PLATFORM_STANDARDS.md`, shared ESLint/Jest config,
`platform-critical`-labelled-PR CI backstop) is now built, rolled out to all
6 app repos, and published as `0.1.0`.

- [ ] Ownership map (repo table in `README.md`/`CLAUDE.md`), CODEOWNERS per
      repo, CONTRIBUTING.md per repo, PR/issue templates, the
      breaking-change/deprecation protocol (14-day adoption window before
      `platform-critical` CI backstop trips — see the design doc's item 4).
      All design-only so far.
- [ ] `mfe-pot-platform` still has no general lint/test/build CI workflow —
      only `publish-shared-packages.yml`, `deploy-eks.yml`, and a new
      `version-check.yml` (`pnpm run check:versions`) exist, despite its own
      `CLAUDE.md` once claiming a single `nx affected` workflow runs there.
- [ ] Real version drift found by the new `check-platform-versions` tool,
      not yet fixed: 5 of 6 app repos are on `shared-ui-scds-core@1.1.0`
      against `platform-versions.json`'s pinned `1.2.0`, and
      `mfe-pot-msca-shell`/`mfe-pot-job-bank-shell` are also on
      `shared-federation-runtime@1.0.2` against the pinned `1.0.1`. Each
      repo's new `check:versions` CI step will fail until addressed (a
      version bump is a separate decision from the rollout itself).
- [ ] Grant `mfe-pot-platform`'s Actions access to
      `@tn4consulting/shared-platform-standards` on GitHub (package →
      Settings → Actions access → add `mfe-pot-platform`) before its next
      version bump — CI-driven publishing 403s without this manual,
      one-time grant, same as it did for the initial `0.1.0` publish (worked
      around manually that time).

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
      `mfe-pot-life-events-mfe`/`dashboard-bff` normally
      make, so the citizen re-enters details separately and sees three
      disconnected status pages. The "before" picture for the demo.
- [ ] Live "tell us once" demo beat — address/bank details entered once in
      the `mfe-pot-life-events-mfe` journey visibly pre-fill the EI
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
      `mfe-pot-life-events-mfe`.
- [ ] Payment-history widget (embedded in `mfe-pot-life-events-mfe`,
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
implemented, published, and confirmed genuinely working end to end on both
the local `kind` cluster and the real AWS EKS deployment: a real citizen
action (`dashboard-bff`'s fan-out) produces one trace ID spanning all 3 BFFs
on both.
Full design, gotchas hit, and exactly what was/wasn't verified live:
`docs/plans/20260808-1630-opentelemetry-observability.md`;
`mfe-pot-platform/CLAUDE.md`'s new "Observability: OpenTelemetry" section is
the durable architecture reference (federation-sharing decision,
per-app-role wiring point, the `propagateTraceHeaderCorsUrls` gotcha).

- [ ] Grafana's public Ingress (`grafana.aws.tn4consulting.com`) is served
      over plain HTTP, not HTTPS — every other public Ingress host in the
      family terminates TLS via cert-manager (`letsencrypt-staging` for now).
      All services should be HTTPS-only; add the same TLS block to
      `mfe-pot-platform/charts/grafana`'s `values-eks.yaml`/Ingress.

## Federation remote-loading integrity — not started

Scoped 2026-08-10, prompted by a question about shell/remote trust
boundaries. `mfe-pot-msca-shell`'s `main.tsx` fetches its federation
manifest (remote names → `remoteEntry.json` URLs) from Strapi's
`/api/remotes` at runtime and hands each URL straight to
`initFederation()`/`loadRemoteModule` with no integrity check —
`mfe-pot-job-bank-shell` presumably follows the same pattern. A compromised
Strapi entry or a MITM'd `remoteEntry.json` response is effectively
arbitrary code execution in the shell's origin, not just tampered content,
since Native Federation fetches and evaluates that JS directly.

- [ ] Design Subresource Integrity (SHA-384) for federated remote loading:
      each remote build emits a hash of its own `remoteEntry.json`
      (and/or exposed chunks), the hash gets published alongside the
      manifest entry (Strapi's `/api/remotes` schema, or the CI publish
      step), and both shells verify it before `loadRemoteModule` executes
      the fetched code.
- [ ] Decide how the hash travels from a remote's own build/CI to Strapi's
      seeded manifest data without becoming another manually-maintained
      cross-repo sync point (`platform-versions.json`-style drift is the
      failure mode to avoid).
      Deliberately not started — real complexity (every one of the 4
      remotes' CI needs to emit and publish a hash, kept in sync across
      independently-deployed repos) for a PoC/demo project; worth doing as
      a dedicated security-hardening pass rather than folded into other
      work.

## Strapi content organization

Strapi's `page-content` collection (`mfe-pot-platform/tools/cms/strapi/`) is a
single flat store for *all* CMS-driven text across all 6 frontend repos —
narrative page intros, table headers, button labels, validation errors — with
the only structure being a dot-path naming convention baked into the `key`
string (e.g. `job-bank.search.table.title`). Nothing in the schema, admin UI,
or `content-seed.ts` encodes or filters on that convention, so the Strapi
admin list is one long undifferentiated scroll. Scoped 2026-08-09; design not
yet implemented.

Recommended approach — add two enum fields to the existing `page-content`
type rather than splitting into multiple content types (kept as one type
deliberately: this is a PoC, and a split would ripple into all 6 apps'
`ContentClient` batch-fetch pattern for no PoC-stage benefit):
- `app` — required enum, reliably derivable with zero guesswork from
  `content-seed.ts`'s own `CONTENT_SOURCES[].name` (it already knows which
  app each entry came from, since it fetches each app's own
  `content-fallback/{en,fr}.json` over HTTP).
- `kind` — optional enum (`label` / `help` / `content` / `message`, no
  default — unset doubles as an admin-UI triage queue). **Not reliably
  derivable**: sampling all 6 apps' `content-fallback/en.json` found ~155 of
  ~160 entries have an empty `body`, including genuinely narrative-shaped
  entries like `job-bank-shell.home.featuredTools.findJob.description` — so
  the assumed "body present ⇒ narrative" signal doesn't actually hold. Needs
  a best-effort key-suffix heuristic in `content-seed.ts` (`error`/
  `unavailable` → `message`, `intro`/`hub-tile` → `content`, `hint`/`help` →
  `help`, else → `label`), set only at entry-creation time and never
  overwritten afterward — matching `seedPageContentEntries`'s existing
  create-only behavior, so a human's admin-UI correction is never silently
  reverted by the cron self-heal task.
- No admin-UI/core-store changes needed — Strapi 5's Content Manager
  auto-generates list-view filters/sorting for any attribute, including new
  enums.

- [ ] Found scoping this: `help`/hint text is a real, currently-unused
      content category, not hypothetical — `scds-text-input`/`scds-picker`/
      `scds-currency-input` (`libs/shared/ui-scds-core`) all have a
      first-class `hint` prop, but there are zero `hint=` usages anywhere in
      `employment-insurance-mfe`'s application wizard and zero `hint`-shaped
      keys in any app's `content-fallback` JSON. Adding a `kind: help` value
      gives this capability somewhere to live once a future pass wires it up.
- [ ] Add `app`/`kind` enum attributes to
      `tools/cms/strapi/src/api/page-content/content-types/page-content/schema.json`
      (both `pluginOptions.i18n.localized: false`, matching the existing
      `key` field — structural metadata, not translatable content).
- [ ] Wire `app`/`kind` into `content-seed.ts`'s `seedPageContentEntries`
      `.create()` call (see above).
- [ ] One-time backfill for the ~160 entries already seeded locally: since
      Strapi's local data is disposable (no PersistentVolume, same posture as
      Redis), simplest is wiping and re-running the local deploy rather than
      a one-off migration script.

## Nx build performance

- [ ] Set up Nx Remote Cache to share build/test/lint cache across the team
      and CI — https://nx.dev/ci/features/remote-cache. Now relevant per-repo
      (each of the 6 repos has its own Nx workspace since the split) rather
      than once across one big workspace.

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

## life-events kit: SCDS/shared-package promotion (considered, deferred)

Surfaced while redesigning `mfe-pot-life-events-mfe` from a schema-driven
model to a page-per-life-event one (see that repo's CLAUDE.md). Two
promotion questions were raised and deliberately deferred rather than
folded into that refactor:

- [ ] `ServiceLinksSection`'s card-grid CSS (`display: grid;
      gridTemplateColumns: repeat(auto-fit, minmax(18rem, 1fr))` around
      `scds-card`) duplicates a pattern `mfe-pot-dashboard-mfe`'s
      `Overview.tsx` independently hand-rolls for its own card grid —
      `shared-ui-scds-core` has no dedicated `scds-card-grid` primitive.
      Real, proven duplication (not speculative); worth promoting a
      presentational-only `scds-card-grid` component into
      `mfe-pot-platform`'s `shared-ui-scds-core`, then adopting it in both
      `life-events-mfe` and `dashboard-mfe`. Cross-repo (touches
      `mfe-pot-platform`, a version bump, two consumers) — a separate task
      from any single app's own work.
- [ ] If `mfe-pot-life-events-mfe` is ever split into separate per-life-event
      repos (today all 5 life events deliberately share one remote — see
      that repo's CLAUDE.md), its `kit/` (`ChecklistSection`,
      `ServiceLinksSection`, `WidgetSlot`, `LifeEventLayout`,
      `bilingual-content.ts`) would need extracting into a new dedicated
      shared package (the family's existing `libs/shared/*` pattern —
      `shared-federation-runtime`, `shared-auth`, etc.), **not** into
      `shared-ui-scds-core`: the kit carries guided-journey-specific
      business logic (`journey.*` i18n keys, widget-loading, completion
      state), not generic design-system primitives, and SCDS is a
      federation-shared singleton deliberately kept low-churn. Not
      actionable now — no such split is planned — but the kit's current
      isolation (own folder, narrow interface) is deliberately kept cheap
      to extract later if it happens, per the family's "extract only once
      there's a proven second consumer" convention.
