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
      `webServer` array: today it only starts `client-profile-service`. Needs
      each of the 5 sibling app repos' `nx serve` pointed at from their
      checkout paths so the composed suite covers all 5 apps again.
- [ ] Push `mfe-frontend-lib`/`mfe-backend-lib` (the two Helm library charts,
      in `mfe-pot-platform`) to a registry as OCI artifacts — every app
      repo's `Chart.yaml` still references them via a sibling-checkout-relative
      `file://` path.
- [ ] AKS + ACR provisioning, then Stage 2 CI (push images to ACR, deploy to
      AKS) per app repo. Blocked on Azure resources not existing yet — see
      `docs/plans/20260801-1935-mfe-pot-polyrepo-split-and-k8s-hosting.md`'s
      "Open items needing your input" for the unresolved questions (domain
      for the 5 hostnames, IaC tool, `az` CLI access).
- [ ] `pnpm demo:reset` — the 4 BFFs hold in-memory state with no reset
      endpoint, so local/CI runs accumulate applications and claims across
      restarts. `mfe-e2e`'s golden-path test already works around this with
      loose assertions instead of exact counts, but a real reset endpoint
      would fix repeatable local/CI runs and live demos alike.
- [ ] Each app repo's `tools/deploy-local.sh` hardcodes `CLUSTER_NAME=kind`,
      but the actual local cluster is named `mfe-pot` (`kind-mfe-pot`
      context) — discovered while redeploying `mfe-pot-dashboard` by hand.
      Running the script as-is would try to create a second, duplicate
      cluster and fail on the port 443 conflict. Fix by making the script
      detect/accept the real cluster name instead of assuming `kind`.
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

- [ ] Add a shared session cache in `mfe-pot-platform` (new `libs/shared/session-cache`
      → `@tn4consulting/shared-session-cache`, following the existing
      `libs/shared/*` naming convention), backed by Redis, that the 4 BFFs'
      classes can use instead of each holding its own independent in-memory
      state. Note the
      tension with the platform's stated policy of minimizing cross-service
      shared state (`client-profile-service` is deliberately its own service
      rather than a shared in-memory lib, to avoid independently-built
      remotes silently diverging) — worth resolving that before building.
      Related to the `pnpm demo:reset` gap above, which exists precisely
      because BFF in-memory state isn't shared/resettable today.

## Demo narrative (proves the point, not just the pattern)

Not started. See `docs/plans/mfe-pot-initial-design.md`'s
"Demo Narrative & Experience" section for the full specifics.

- [ ] Siloed-mode toggle in `mfe-pot-shell` — disables the cross-service calls
      `mfe-pot-employment-life-events`/`dashboard-bff` normally
      make, so the citizen re-enters details separately and sees three
      disconnected status pages. The "before" picture for the demo.
- [ ] Live "tell us once" demo beat — address/bank details entered once in
      the `mfe-pot-employment-life-events` journey visibly pre-fill the EI
      application and Job Bank profile, actually crossing the
      `client-profile-service` boundary.
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
      `mfe-pot-platform`'s `client-profile-service`, the actual data owner)
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
- [ ] **New bug found, unrelated to SCDS**: `mfe-pot-shell` fails to load
      `mfe-pot-job-bank` as a federated remote at all —
      `SyntaxError: The requested module 'blob:...' does not provide an
      export named 'useState'`. Root cause: job-bank's own build emits its
      shared `react.js` chunk as a CommonJS-wrapped **single default
      export** (`export default J()`, `J()` returning the whole CJS
      `module.exports`), not real named ESM exports — the shell's
      native-federation runtime can't destructure `useState` etc. from
      that. **Confirmed pre-existing**, not a regression from the SCDS
      work: checked out job-bank's prior commit in a scratch worktree,
      rebuilt, and the exact same `export default J()` bundle shape
      appears. Likely never caught before because job-bank is the only
      React remote in the family (no other remote exercises the
      shell's cross-remote React-sharing path), and this specific
      shell→job-bank interactive path hadn't been manually verified in a
      browser before. Also saw a second, likely-related console error
      on the same page load: `[NF] Failed to load module
      job-bank/./RemoteProviders: Exposed module './RemoteProviders' from
      remote 'job-bank' not found in storage` — job-bank has never
      exposed a `./RemoteProviders` module (that's a dashboard-specific
      expose), so the shell may be assuming every remote has one.
      job-bank works correctly standalone (own origin, no shell) with
      zero console errors — this is purely a shell-mediated federation
      loading issue.
