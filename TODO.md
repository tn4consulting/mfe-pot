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
      the one thing it used to start, has been removed entirely — its
      payments/correspondence data now lives directly in `dashboard-bff`'s
      own local `data.ts`). Needs each of the 5 sibling app repos' `nx serve`
      pointed at from their checkout paths so the composed suite covers all
      5 apps again.
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

## Stale Firebase-era functionality to remove

Firebase Hosting itself was already retired (`firebase.json`/`.firebaserc`
gone, `mfe-pot-platform/CLAUDE.md`'s "Hosting" section says so) but a few
things built specifically to cope with Firebase's constraints (can't run
Strapi, so needed baked-in static fallbacks) are still sitting in the
codebase now that the target hosting environment is Kubernetes (AKS in the
cloud, `kind` locally — both of which run Strapi directly, including for
local dev):

- [ ] `mfe-pot-platform/libs/shared/remote-registry`'s
      `StaticRemoteRegistryProvider` — genuinely dead code, not just
      redundant: nothing constructs it anymore (`mfe-pot-shell/apps/shell/src/main.ts`
      only wires up the Strapi-backed `StrapiRemoteRegistryProvider`). Its own
      doc comment still says "Firebase-hosted demo: Firebase Hosting can't
      run Strapi...". Safe to delete outright, plus the interface/export
      wiring pointing at it.
- [ ] `StaticContentClient` (`mfe-pot-platform/libs/shared/content-client`) —
      unlike the above, still live: `createContentClient()` in each of
      `mfe-pot-dashboard`/`mfe-pot-job-bank`/`mfe-pot-employment-insurance`/
      `mfe-pot-employment-life-events`'s `content-client.token.ts` falls back
      to it when `strapiBaseUrl` is undefined, with the baked `STATIC_CONTENT`
      map explicitly commented "Baked fallback for the Firebase-hosted build
      (no live CMS there)". Needs a decision, not just a delete: now that
      Strapi is deployed alongside every app (cloud and local `kind` alike),
      is `strapiBaseUrl` ever legitimately undefined at runtime, or was that
      only ever a Firebase-shaped code path? If the latter, remove
      `StaticContentClient`, `STATIC_CONTENT`, and the fallback branch in all
      4 apps; if there's still a real "Strapi unreachable" degrade case worth
      keeping, keep it but reword the comments so they stop citing Firebase.
- [ ] `mfe-pot-platform/.claude/settings.local.json` still allowlists
      `Bash(firebase deploy *)` — dead permission entry, no `firebase` CLI
      command exists to run anymore.
- [ ] Lower priority, cosmetic only: `tools/docker/nginx.conf` (same file
      copied into all 5 frontend-app repos) and each repo's `.gitignore`
      still reference "the old firebase.json"/"retired Firebase Hosting" in
      comments. Accurate history, not broken functionality — fine to leave,
      but worth a pass if these ever get confusing next to actual dead-code
      removal above.

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

## Observability

- [ ] OpenTelemetry across the 3 BFFs (and ideally the frontends) with a
      propagated trace ID, so a single citizen action can be followed across
      service boundaries — e.g. `mfe-pot-employment-life-events` calling into
      `dashboard-bff`/`job-bank-bff`/`employment-insurance-bff`. No
      logging/tracing/correlation-ID infrastructure exists anywhere in the
      family today (checked all 3 BFFs and all 5 frontend repos — no
      `winston`/`pino`/logger, no `x-request-id` or correlation-ID handling).
      Natural fit alongside the "BFFs must not call each other" design
      principle above, since tracing is what would make cross-BFF/backend
      call chains debuggable once they exist.

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
have-a-representative, omnichannel-support. Dashboard is done; `mfe-pot-shell`
has no local routes beyond the 4 federated remotes; no profile/inbox/
notification UI exists anywhere.

Decided approach: build one vertical slice at a time rather than all 6 at
once.

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
