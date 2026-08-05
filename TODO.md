# TODO

Outstanding work across the whole mfe-pot family (all 6 repos). Lives here,
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
      the one thing it used to start, has been removed entirely — see
      "`client-profile-service` removed" below). Needs each of the 5 sibling
      app repos' `nx serve` pointed at from their checkout paths so the
      composed suite covers all 5 apps again.
- [x] **`client-profile-service` removed** (`mfe-pot-platform`, was port
      3003) — it had no Helm chart, so its one caller (`dashboard-bff`'s
      `/api/payments`) 502'd in any real deployment. Its payments/
      correspondence data now lives directly in `dashboard-bff`'s own local
      `data.ts` (`mfe-pot-dashboard`), the same in-memory-stub pattern
      `job-bank-bff`/`employment-insurance-bff` already use for their own
      domains — the 502 is gone for good, no upstream call left to fail.
      **Tradeoff**: the service existed specifically so this data was one
      shared source across all three domain BFFs, not a disconnected
      per-remote copy (its own doc comment said so) — folding it into
      `dashboard-bff` makes it dashboard-only. See the "tell us once" demo
      beat below, which this narrows.
- [ ] Push `mfe-frontend-lib`/`mfe-backend-lib` (the two Helm library charts,
      in `mfe-pot-platform`) to a registry as OCI artifacts — every app
      repo's `Chart.yaml` still references them via a sibling-checkout-relative
      `file://` path.
- [ ] AKS + ACR provisioning, then Stage 2 CI (push images to ACR, deploy to
      AKS) per app repo. Blocked on Azure resources not existing yet — see
      `docs/plans/20260801-1935-mfe-pot-polyrepo-split-and-k8s-hosting.md`'s
      "Open items needing your input" for the unresolved questions (domain
      for the 5 hostnames, IaC tool, `az` CLI access).
- [ ] `pnpm demo:reset` — each of the 3 BFFs now has its own `POST
      /api/reset` (see "Shared BFF session cache" below), but there's still
      no single cross-repo command that calls all 3 (this meta repo has no
      root `package.json` to hang one off), and the BFF pods running on
      `kind` today are still on the old in-memory code, not yet rebuilt
      against the real published `@tn4consulting/shared-session-cache`. A
      small script (a curl loop over the 3 BFFs' URLs) most naturally
      belongs in `mfe-pot-platform`'s `apps/mfe-e2e`, which already
      coordinates all the sibling repos for the composed test suite.
      `mfe-e2e`'s golden-path test still works around the underlying gap
      with loose assertions instead of exact counts in the meantime.
- [x] Each app repo's `tools/deploy-local.sh` hardcoded `CLUSTER_NAME=kind`,
      but the actual local cluster is named `mfe-pot` (`kind-mfe-pot`
      context) — discovered while redeploying `mfe-pot-dashboard` by hand,
      reconfirmed 2026-08-03 hitting the same failure in `mfe-pot-shell`
      (script tried to create a second `kind` cluster, died on the port
      80/443 conflict with the already-running `kind-mfe-pot` one). Fixed
      2026-08-04 in the last 2 stragglers (`mfe-pot-shell`,
      `mfe-pot-employment-life-events` — the other 3 already had it) by
      accepting a `CLUSTER_NAME` env override instead of hardcoding `kind`,
      needed so `mfe-pot/tools/deploy-local.sh` (new, see below) can target
      the real cluster name when orchestrating all 6 repos at once.
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
- [ ] `mfe-pot-platform`'s `shared-ui-gcds` build fails in a fresh CI
      checkout with `TS5062: Substitution '.../core' in pattern
      '@tn4consulting/shared-auth/core' can have at most one '*' character`
      (ng-packagr's full-compilation-mode build against
      `tsconfig.base.json`'s `@tn4consulting/shared-auth/core` path
      mapping). Discovered getting `publish-shared-packages.yml` to actually
      run end to end for the first time (see below) — every prior run of
      that workflow had failed earlier in the job, so this is likely the
      first time `shared-ui-gcds:build` has run in CI at all, not a
      regression. `publish-shared-packages.yml` publishes `shared-ui-scds`
      before `shared-ui-gcds` specifically so this doesn't block the former.

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
      concrete Redis requirement for the shared-session-cache work already
      tracked below.
- [ ] A/B testing as a first-class design principle — changes must be
      testable at small scale for impact before full rollout.

## Shared BFF session cache

- [x] Added a shared session cache in `mfe-pot-platform`
      (`libs/shared/session-cache` → `@tn4consulting/shared-session-cache`,
      following the existing `libs/shared/*` naming convention): a minimal
      `SessionCache` interface (`getJson`/`setJson`/`reset`/`buildKey`) with
      two implementations, `RedisSessionCache` (real `ioredis` client) and
      `InMemorySessionCache` (the `nx serve` default when `REDIS_URL` isn't
      set, and what unit tests inject — no real Redis needed in CI). Each of
      the 3 BFFs (`dashboard-bff`, `job-bank-bff`, `employment-insurance-bff`)
      now uses its own namespaced instance (`keyPrefix`) instead of a
      module-level array/Map — a connection/serialization helper, not shared
      business state, so the cross-service-shared-state tension noted below
      doesn't actually apply. Each BFF also gained a `POST /api/reset`
      (no auth, PoT-only) that clears just its own prefix — the piece that
      unlocks `pnpm demo:reset` above (the actual cross-repo reset script is
      still a follow-up, most naturally living in `mfe-pot-platform`'s
      `apps/mfe-e2e`). Id generation in `job-bank-bff`/`employment-insurance-bff`
      switched from array-length-derived (`app-${n+1}`) to `crypto.randomUUID()`
      — a necessary correctness fix, not cosmetic, since array-length ids
      silently collide once state outlives a single process.
      New `mfe-pot-platform/charts/session-cache` (plain `redis:7-alpine`,
      no persistence/no auth — a resettable PoT demo cache, not durable or
      sensitive storage, same posture as `charts/strapi`'s dummy secrets) is
      deployed once, independently of any per-app chart, same as
      `charts/strapi` — folded into `tools/deploy-local.sh`. All 3 BFF
      charts' `values.yaml` point `REDIS_URL` at its in-cluster Service DNS
      (`session-cache.default.svc.cluster.local:6379`).
      Verified live on the `kind` cluster: the chart deploys and passes its
      `redis-cli ping` readiness probe, a throwaway debug pod confirms the
      same Service DNS the BFFs use actually resolves and responds, and the
      real (non-mocked) `RedisSessionCache` — via a local port-forward —
      round-trips a JSON value and `reset()`s correctly against it.
      **Not yet done**: the 3 BFFs' own pods still run the old in-memory
      code. Their Dockerfiles' `pnpm install --frozen-lockfile` runs inside
      a build context scoped to each repo's own root, so they need the real
      published `@tn4consulting/shared-session-cache` package from GitHub
      Packages, not a local link — i.e. `publish-shared-packages.yml` needs
      to actually run (already wired to publish this package) before any of
      the 3 BFF repos can bump their dependency off the temporary
      `file:../mfe-pot-platform/libs/shared/session-cache` reference each
      currently carries and get their images rebuilt/redeployed to `kind`.

## Demo narrative (proves the point, not just the pattern)

Not started. See `docs/plans/mfe-pot-initial-design.md`'s
"Demo Narrative & Experience" section for the full specifics.

- [ ] Siloed-mode toggle in `mfe-pot-shell` — disables the cross-service calls
      `mfe-pot-employment-life-events`/`dashboard-bff` normally
      make, so the citizen re-enters details separately and sees three
      disconnected status pages. The "before" picture for the demo.
- [ ] Live "tell us once" demo beat — address/bank details entered once in
      the `mfe-pot-employment-life-events` journey visibly pre-fill the EI
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
      `mfe-pot-employment-life-events`.
- [ ] Payment-history widget (embedded in `mfe-pot-employment-life-events`,
      sourced from `mfe-pot-dashboard`) still renders static English mock
      data — heading, benefit names, dates, currency — none of it wired to
      Transloco/locale-aware formatting yet. A prerequisite for the bilingual
      demo beat above.

## Language support

- [ ] Add Cree and Inuktitut (`cr`/`iu`) alongside English/French. Scoped by
      an exploration pass — key points:
      - `SUPPORTED_LOCALES` in `mfe-pot-platform/libs/shared/i18n/src/lib/locale-sync.ts`
        is the single source of truth for the `Locale` type and is
        N-language-ready (just an array) — but several places hand-roll
        their own `'en' | 'fr'` union instead of importing `Locale`, and need
        manual updates: `mfe-pot-platform/libs/shared/content-client`'s
        `ContentClient` interface, `StrapiContentClient`,
        `StaticContentClient`, and `mfe-pot-dashboard`'s static content
        fallback map (`apps/dashboard/src/app/app.ts`).
      - The shell's language switcher (`MscaAppFrame` in
        `mfe-pot-platform/libs/shared/ui-gcds`) is a strict binary toggle
        (`otherLocale`/`switchLocale`), not a picker — needs to become a
        dropdown/menu for 4 languages. GCDS has no built-in multi-language
        picker to reuse (`gcds-header`'s `toggle` slot and `gcds-lang-toggle`
        are both designed for exactly one "other" language).
      - **Hard ceiling**: `@gcds-core/components` (v1.4.0) is officially
        bilingual-only. Its `assignLanguage()` util
        (`dist/collection/utils/utils.js`) collapses any non-`fr*` lang to
        `'en'`, and internal validation-error strings
        (`utils/i18n/validation-errors.js`) are a closed `{en, fr}`
        dictionary with no fallback branch. There is no supported way to get
        GCDS's own internal chrome (form validation messages, built-in ARIA
        text) to render in Cree/Inuktitut without forking/patching upstream
        (`cds-snc/gcds-components`) — check upstream GitHub issues before
        committing to that. App-level Transloco-driven content can still
        switch fully; GCDS's own internal strings can't.
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
have-a-representative, omnichannel-support. Almost none of it exists yet —
`mfe-pot-dashboard`'s `apps/dashboard` today is just a CMS welcome blurb + a
2-row payment-history widget; `mfe-pot-shell` has no local routes beyond the
4 federated remotes; no profile/inbox/notification UI exists anywhere.

Decided approach: build one vertical slice at a time rather than all 6 at
once.

- [x] **Dashboard screen** (`dashboard.png` + `benefit-application-status.png`)
      — done: `mfe-pot-dashboard` now has a real `feature-overview` lib
      (`DashboardFeatureOverview`) rendering greeting/date/breadcrumb, mock
      What's New / Needs Attention / Consider This sections (GCDS
      `gcds-notice`/`gcds-card`), and three **real, BFF-backed** widgets —
      My Tasks (now synthesized from live EI reporting status, not a static
      string), EI Reporting Status ("days until next report due", computed
      by a new `employment-insurance-bff` `/api/reporting-status` endpoint
      since no reporting-cadence concept existed anywhere before), and My
      Job Applications (sourced from `job-bank-bff`, now denormalizing
      job title/employer onto `/api/applications`). `feature-payment-history`
      also gained `program`/`status` columns end-to-end (including
      `mfe-pot-platform`'s `client-profile-service`, the actual data owner
      at the time — since removed, its data now lives in `dashboard-bff`
      itself, see "Hosting / CI" above)
      rendered as a real HTML table. All new BFF/frontend code has Jest
      coverage (including a `jest-axe` pass on the new component); the
      repo-wide "no axe tooling" gap otherwise still stands. Benefit-
      application-status's "My Active Programs" concept is now covered by
      the EI Reporting Status / My Job Applications cards rather than a
      separate screen. Old plan reference
      (`~/.claude/plans/lovely-wandering-engelbart.md`) is superseded by
      `~/.claude/plans/using-todo-list-and-vivid-mountain.md`.
- [ ] Profile screen (`profile.png`) — My Profile/Preferences/Authorizations/
      Security tabs, personal/contact/family info, sidebar links (Message
      Centre, Payments History, Notifications, Document Centre). Natural
      owner is `mfe-pot-dashboard` per the "tell us once" profile domain
      boundary.
- [ ] Inbox screen (`inbox.png`) — message list with program/date/has-PDF
      filters. No natural app owner yet identified; likely a new
      `mfe-pot-shell`-level local route (global nav concern) backed by a
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

## Design system extension (SCDS)

- [x] Extend the design system beyond GCDS, while staying GCDS-compatible —
      working name "Canada Design System" (SCDS). Home: new
      `libs/shared/ui-scds` in `mfe-pot-platform`, published as
      `@tn4consulting/shared-ui-scds`, following the exact scaffold pattern
      of the existing `libs/shared/ui-gcds` (ng-packagr, its own publish
      step in `publish-shared-packages.yml`).
- [x] Multi-column list component (e.g. a list of tasks or documents) —
      `ScdsMultiColumnList`: `items`/`columns` array (`cell: (item:
      unknown) => string` per column — the original Angular-only
      `TemplateRef` escape hatch was dropped in the later Stencil rewrite,
      see below, since there's no cross-framework equivalent and no real
      consumer needed it), real `<ul role="list">`/`<li role="listitem">`
      markup, CSS Grid columns collapsing to stacked "label: value" rows at
      GCDS's own 48em breakpoint, each cell's column header always present
      as real (not CSS-generated) text for assistive tech.
      `mfe-pot-dashboard`'s `dashboard-tasks-list` is the first real
      consumer (single-column today, since `dashboard-bff`'s task model is
      still plain strings — a richer `{title, dueDate}` task shape is a
      possible follow-up, not done here).
- [x] Card component (e.g. dashboard widgets) — `ScdsCard`: composes
      alongside real `gcds-card` in "link" mode, but renders its own markup
      in a "static" (non-navigating) mode — a genuine GCDS gap: bare
      `gcds-card` requires `href` and renders nothing without it. Adds a
      severity tone badge (reusing `gcds-notice`'s tone/icon vocabulary)
      and a footer actions slot GCDS has no equivalent for.
      `mfe-pot-dashboard`'s `dashboard-consider-this-list` is the first real
      consumer, replacing its old `href="#"` dead-link workaround with the
      static variant.
      `@tn4consulting/shared-ui-scds@0.1.0` was published and confirmed
      working live: `mfe-pot-dashboard` installed the real registry
      package (not the dev-time `file:` link), redeployed to the local
      `kind` cluster, and both components render correctly through the
      shell's federated `/dashboard` route with real data.
- [x] Adopt SCDS beyond `mfe-pot-dashboard`. Real fits found only in
      `mfe-pot-employment-insurance` (3 `ScdsCard` candidates: claim
      status, reporting status, application confirmation) and
      `mfe-pot-job-bank` (job postings list, applications list) —
      `mfe-pot-shell`/`mfe-pot-employment-life-events` have no card/list UI
      to convert. `job-bank`'s frontend is **React**, and critically
      consumed *no* custom elements at all before this (not even GCDS's
      own) — a pure-Angular `shared-ui-scds` could never reach it.
      **Rebuilt both components as framework-agnostic Stencil custom
      elements** (`@tn4consulting/shared-ui-scds-core`, new package in
      `mfe-pot-platform`), mirroring exactly how GCDS itself is built and
      shipped (`@gcds-core/components` is Stencil; its Angular wrapper is
      auto-generated via `@stencil/angular-output-target` — confirmed by
      inspecting the installed package). Published and live. Real
      shadow-DOM fixes this rewrite needed that the Angular version didn't:
      `<ng-content select>` → named `<slot>`s, the ARIA-IDREF
      `listLabelledBy` prop dropped (can't cross a shadow boundary),
      `:empty` CSS → `:not(:has(::slotted(*)))`. Also drops the
      Angular-only `column.template` `TemplateRef` escape hatch — no
      web-component equivalent, no real consumer needed it.
      `mfe-pot-job-bank`'s `FeatureSearch`/`JobApplicationsList` now
      consume `scds-multi-column-list` directly (items/columns set
      imperatively via DOM properties, registered once via a small
      `register-scds.ts` module imported from both federation-exposed
      entry points — `bootstrap.tsx` never runs when federated, a real
      bug caught before it shipped). **Verified working standalone**
      (real screenshot: a clean multi-column job-postings table, zero
      console errors) — see the new bug immediately below for why it
      isn't yet verified through the shell.
- [x] `shared-federation-config`'s pin aligned to `^0.4.0` (the new
      `@tn4consulting/shared-ui-scds-core` singleton entry) across all 5 app
      repos, not just the ones with SCDS changes this round — a drifted pin
      here is exactly how federation singleton mismatches happen silently.
- [x] Regenerated `shared-ui-scds`'s Angular wrapper from the Stencil core
      via `@stencil/angular-output-target` (`outputType: 'standalone'`,
      `customElementsDir: 'dist/components'` — the package deliberately has
      no `exports` map, matching `@gcds-core/components`'s own layout, so
      the generated proxy's import paths have to match the real physical
      dist-custom-elements output location). Deleted the hand-written
      `ScdsCard`/`ScdsMultiColumnList` Angular components entirely.
      `@tn4consulting/shared-ui-scds-core` is a peerDependency (ng-packagr
      won't publish non-peer deps), alongside `rxjs` (needed by the
      generated proxy's output-binding helper). Published as
      `@tn4consulting/shared-ui-scds@0.2.0`.
      Two non-obvious build issues surfaced getting this to actually
      compile: Nx's buildable-libraries support silently substitutes a
      local-source path mapping for the *bare* `@tn4consulting/shared-ui-scds-core`
      specifier (since it's itself an Nx project in this same workspace),
      which resolves to a directory with no co-located `.d.ts` — fixed by
      importing from the `/dist/components` subpath instead, same as the
      generated proxy file already does. And any app statically importing
      the regenerated wrapper (as opposed to job-bank's loader-based lazy
      consumption) needs `@stencil/core` as a **real** dependency, since
      the dist-custom-elements output deliberately externalizes
      `@stencil/core/internal/client` rather than bundling it — plus
      `@stencil` added to each consuming repo's jest
      `transformIgnorePatterns` allowlist (same ESM-only-`.js` issue as
      `@gcds-core`).
      `mfe-pot-dashboard` migrated to `^0.2.0`: `<div scdsCardActions>` →
      `<div slot="scdsCardActions">` (native slots match the `slot`
      attribute, not an arbitrary attribute selector) and
      `listLabelledBy="tasks-heading"` → `listLabel="My Tasks"` (an
      ARIA IDREF can't cross a shadow boundary). `ScdsListColumn` also lost
      its generic type parameter in the Stencil rewrite. Specs that
      inspected `ScdsMultiColumnList`'s rendered rows now query through the
      custom element's `shadowRoot` with a render-tick wait instead of the
      host's plain `textContent`/`querySelector` — `ScdsCard`'s own specs
      needed no such change, since its body/actions content stays in light
      DOM (slotted), only `ScdsMultiColumnList`'s rows are shadow-rendered.
      Redeployed to `kind` and reverified through the shell's `/dashboard`
      route: both components still render correctly with real data, zero
      new console errors.
- [x] Adopted `ScdsCard` in `mfe-pot-employment-insurance`'s 3 candidates:
      `feature-claims` (success tone for approved claims),
      `feature-reporting-status` (replaced the hand-rolled `.status-pill`
      CSS, now deleted, with the tone badge — overdue → danger, due_soon →
      warning, not_yet_due → no tone), and `feature-applications` (the
      confirmation-state card; confirmed `role="status"` carries over onto
      the custom element's host fine, since Stencil doesn't strip
      unrecognized attributes — verified against the real build rather
      than assumed). Same repo also had the `CLUSTER_NAME=kind`
      `deploy-local.sh` bug (see above), fixed here too. Redeployed to
      `kind` and verified live through the shell: claim status, the
      EI-apply confirmation card, and their tone badges all render
      correctly, zero new console errors.
- [x] `mfe-pot-shell` failed to load `mfe-pot-job-bank` as a federated
      remote — `SyntaxError: ... does not provide an export named
      'useState'`. Root cause, confirmed by inspecting the actual built
      shared `react.js` chunk directly: `apps/job-bank/build/build.mjs`
      and `serve.mjs` passed `adapterConfig.frameworks: []` to
      `@softarc/native-federation-esbuild`'s `runEsBuildBuilder`, to avoid
      `reactFrameworkPlugin()`'s hardcoded dev/prod `fileReplacements` map
      (stale against React 19's renamed CJS filenames). That also silently
      dropped the *other*, unrelated thing the framework plugin sets —
      `needsCommonJsPlugin: true`, which is what makes
      `node-modules-bundler.js` load `@chialab/esbuild-plugin-commonjs`
      for shared node_modules chunks. Without it, esbuild's own default
      CJS→ESM interop was used instead, which only synthesizes named
      exports it can statically prove are used *within the same build
      graph* — a shared chunk built as its own standalone entry point has
      none to find, so it degraded to one `export default` wrapping the
      whole `module.exports` object (every hook really was on it, just not
      as a real named export). Fixed by passing
      `frameworks: [{ needsCommonJsPlugin: true }]` instead of `[]` in both
      files — keeps the CJS-interop plugin (which does real static
      analysis of the CJS module's own exports, not the importer's usage)
      without reintroducing the stale file-replacement paths. Verified: the
      rebuilt shared chunk now ends in a real `export { ... useState, ... }`
      statement; `nx test job-bank` still passes; redeployed both
      `job-bank` and `shell` (which also needed a redeploy — its running
      pod predated the `Mount job-bank as a react-kind remote` commit,
      which was the separate cause of a `./RemoteProviders`-not-found
      console error seen alongside this) to the local `kind` cluster and
      confirmed the deployed job-bank chunk now exports `useState` by
      name.
      **Second, deeper bug surfaced once the above was fixed**: shell then
      threw `Dynamic require of "react" is not supported` from inside
      `createRoot` (react-dom's own chunk). Root cause: react-dom is a CJS
      package that internally does `require('react')` to reach React's
      shared internals, and in
      `@angular-architects/native-federation`'s shared-chunk build path
      (`node-modules-bundler.js`), `createAngularLinkerPlugin()`'s `onLoad`
      handler claimed *every* `.js` file passing through, even ones that
      never needed Angular linking, whenever `advancedOptimizations`
      (`= !dev`, i.e. always true for a production build) was set —
      permanently consuming esbuild's onLoad slot before
      `@chialab/esbuild-plugin-commonjs` (registered after it) ever got a
      turn, so react-dom's internal `require('react')` never got converted
      to a real import and esbuild's own fallback interop can't resolve a
      `require()` of an externally-shared module.
      First attempt (un-sharing `react-dom`/`react-dom/client` as
      federation singletons entirely) turned out to be a dead end: react-dom
      still failed with the identical error, just moved to Angular's
      regular app-bundle pipeline instead, which doesn't wire in the
      CJS-interop plugin at all — same underlying problem, different
      symptom location. Reverted that.
      **Real fix**: `pnpm patch @angular-architects/native-federation`
      (patch committed at
      `mfe-pot-shell/patches/@angular-architects__native-federation.patch`,
      registered in `package.json`'s `pnpm.patchedDependencies` — the
      Dockerfile also needed `COPY patches ./patches` added before
      `pnpm install`, since the image build wouldn't otherwise have the
      patch file available to apply). Changed
      `createAngularLinkerPlugin`'s condition from
      `if (!needsLinking && !advancedOptimizations) return null` to
      `if (!needsLinking) return null` — always pass through when a file
      genuinely doesn't need Angular's linker (per the existing, precise
      `requiresLinking()` check), regardless of `advancedOptimizations`,
      so react-dom correctly falls through to the CJS-interop plugin while
      Angular libraries that do need linking are unaffected (kept
      plugin *order* as originally shipped — `[linker, commonjs]` — a
      same-file reorder attempt independently caused a regression: any file
      the linker plugin would otherwise correctly claim instead got
      swallowed by the commonjs plugin first, leaving raw un-linked
      `ɵɵngDeclareFactory`/`ɵɵngDeclareInjectable`/etc. calls in the output,
      which surfaced as `Error: JIT compiler unavailable` at runtime for
      `@angular/common`'s shared chunk — the JIT compiler isn't bundled in
      a production build, so anything left unlinked crashes instead of
      falling back).
      **Verified three times over** (worth noting since the first two
      "fixed" attempts both looked plausible until tested against the real
      deployed bundle): zero `Dynamic require` string matches and zero
      literal `require(...)` call sites survive anywhere in the deployed
      shell pod's JS; zero unlinked `ɵɵngDeclare*` *call sites* remain
      (the one remaining string match, in `@angular/core`'s own chunk, is
      that package's public export list of the linker-helper functions
      themselves — expected, matches `requiresLinking()`'s own deliberate
      `@angular/core`/`@angular/compiler` exclusion). Also hit, and had to
      work around, the project's own documented "Dev-server caching
      gotcha" (`mfe-pot-platform/CLAUDE.md`) mid-investigation: iterating
      on the patch locally without clearing `mfe-pot-shell/.angular` served
      a stale pre-patch copy of the federation builder logic, making a
      correct fix look like a no-op — `rm -rf .angular
      node_modules/.cache/native-federation` before each local rebuild
      fixed that; not an issue for the Docker image build itself, which
      always starts fresh. `nx test shell` passes; rebuilt (`--no-cache`)
      and redeployed to `kind`; this is a genuine upstream bug in
      `@angular-architects/native-federation` worth reporting, not
      something wrong in this codebase.
      Not yet done: `mfe-pot-job-bank/apps/job-bank/federation.config.mjs`
      still declares `react-dom`/`react-dom/client` as shared too — inert
      today (job-bank never imports them), harmless, left as-is.
      **Third bug, surfaced once the first two were fixed**: job-bank then
      failed with `Unable to resolve specifier
      '@tn4consulting/shared-ui-scds-core/loader'` (on both the routed
      `/job-bank` page and the dashboard's embedded job-applications
      widget). Root cause: `register-scds.ts` imports
      `defineCustomElements` from the Stencil-generated `/loader` subpath,
      but `shared-federation-config/react.js`'s
      `sharedGcdsFederationDependency` only declares the bare
      `@tn4consulting/shared-ui-scds-core` specifier as shared, with
      `includeSecondaries: false` (deliberately, to dodge the
      already-documented `react/jsx-runtime` auto-discovery bug) — so the
      `/loader` subpath was never in the shared import map at all. This
      route (both the standalone job-bank page and the dashboard-embedded
      widget) had evidently never been exercised end to end through the
      shell before. Fixed locally in
      `mfe-pot-job-bank/apps/job-bank/federation.config.mjs`: added an
      explicit `share({'@tn4consulting/shared-ui-scds-core/loader': {...same
      singleton shape}})` entry alongside the existing shared config,
      rather than editing the published platform package (smaller,
      contained, no cross-repo package-publish/version-bump needed since
      nothing else in the family imports this subpath). Verified: rebuilt
      job-bank's `remoteEntry.json` now lists both
      `@tn4consulting/shared-ui-scds-core` and its `/loader` subpath as
      shared; `nx test job-bank` passes; redeployed to `kind`.
      **Not yet folded into the published package**: this fix lives only
      in job-bank's local federation config. If `shared-ui-scds-core`
      ever grows another consumer of `/loader` (or any other subpath),
      the real fix belongs in `shared-federation-config/react.js` itself
      (a version bump + pin update across consuming repos) rather than
      each repo re-patching around it independently.
