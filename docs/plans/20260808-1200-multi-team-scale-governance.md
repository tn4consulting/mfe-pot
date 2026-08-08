# mfe-pot: multi-team scale governance

## Status

In progress. Item 3 (below) — a published `@tn4consulting/shared-platform-standards`
package carrying a version-enforcement CLI, a Claude-readable standards doc,
and shared ESLint/TypeScript/Jest config — is being built now, piloted on
`mfe-pot-dashboard-mfe`. Everything else in this doc (CODEOWNERS,
CONTRIBUTING.md, the breaking-change protocol, PR/issue templates, ownership
map) is design-only, tracked as backlog in `../../TODO.md`'s "Scaling to
multi-team ownership" section.

## Context

mfe-pot was built solo (one person/agent across all 7 repos), and that
shows in what's missing: strong *technical* contracts already exist
(published `@tn4consulting/shared-*` packages, `platform-versions.json`,
`@nx/enforce-module-boundaries`, per-repo CI with `kind` validation and now
real AWS EKS deploy, a shared Renovate preset) but there is **zero
coordination/governance tooling** — no CODEOWNERS anywhere, no
CONTRIBUTING.md anywhere, no PR/issue templates, no documented
breaking-change protocol, no ownership map. `mfe-pot-platform` itself also
has **no lint/test/build CI workflow at all** — only `publish-shared-packages.yml`
and `deploy-eks.yml` exist, despite its own `CLAUDE.md`'s "Source control &
CI/CD" section claiming a single `nx affected` workflow runs there. That's a
real, separate, pre-existing gap — tracked in `TODO.md`, not solved here.

**Decisions this doc locks in**:
- **One team per repo** — 7 teams total. `mfe-pot-platform` is the
  platform/DX team, serving the other 6 as internal customers.
- **Stay PoT-grade** — the gap to close is *process*, not *rigor*.
  Preventing teams from silently breaking each other matters; adding
  security/compliance hardening (threat modeling, secrets management, audit
  logging) is explicitly out of scope for this doc.
- **The single highest-risk failure mode specific to going multi-team**:
  Native Federation's shared-singleton contract "fails at runtime with no
  compile-time warning across repos" (stated twice in
  `mfe-pot-platform/CLAUDE.md`). One maintainer self-polices that today by
  holding the whole picture in their head. At 7 independent teams, someone
  *will* bump `react` or `shared-ui-scds-core` in their own repo without
  realizing it drifts the singleton contract — and the failure mode is a
  silent blank-page/broken-widget in production, not a build error. This is
  why item 3 below was built first, ahead of the rest of this doc.
  **Confirmed live, not hypothetical**: as of this doc, `platform-versions.json`
  pins `sharedUiScdsCore` at `1.2.0`, but `mfe-pot-dashboard-mfe/package.json`
  still declares `^1.1.0` — real, present drift, exactly the kind item 3's
  CLI is built to catch.

## 1. Ownership map

Add an "Owning team" column to the repo table in `mfe-pot/README.md` and
`mfe-pot/CLAUDE.md` — the one place that already sits above all 7 repos, so
the natural home for "who do I talk to about X." Don't invent a second
registry elsewhere.

## 2. CODEOWNERS, per repo

- Each of the 6 app repos: `.github/CODEOWNERS` naming that repo's owning
  team as default owner for everything.
- `mfe-pot-platform`: default owner is the platform team, with extra-scrutiny
  paths named explicitly (same owner today, but documents *why* these are
  higher-blast-radius, and sets the file up for when platform work splits
  further): `libs/shared/*`, `platform-versions.json`, `default.json`
  (Renovate preset), `charts/mfe-frontend-lib`, `charts/mfe-backend-lib`,
  `infra/terraform/*`.
- `mfe-pot` (this meta repo): platform team is the default merger, but
  **not** gated to platform-team authorship — any team can propose a
  `TODO.md`/`docs/plans/` change, since those documents describe
  cross-cutting work platform doesn't unilaterally own.

## 3. `@tn4consulting/shared-platform-standards`

Built as real code, not just designed here — see the package itself
(`mfe-pot-platform/libs/shared/platform-standards`) for the authoritative
detail. Summary of what it does, since it's the anchor the rest of this doc
builds on:
- **`check-platform-versions`** (CLI): fetches `platform-versions.json` live
  from `mfe-pot-platform`'s `main` by default (no sibling clone needed —
  every MFE developer works standalone), checks *resolved* versions of the
  federation-shared singleton packages against it, fails CI with a clear
  diff on drift.
- **`sync-platform-standards`** (CLI, runs on `postinstall`): copies a
  curated `PLATFORM_STANDARDS.md` — the non-negotiable cross-repo rules
  (bilingual/WCAG/SCDS requirements, the federation-sharing policy, the BFF
  boundary rules, the linting policy) — into each consuming repo's
  `docs/PLATFORM_STANDARDS.md`, `@`-imported from that repo's own
  `CLAUDE.md`. Fixes a real dead reference: every app repo's `CLAUDE.md`
  today points at `../mfe-pot-platform/CLAUDE.md`, which doesn't exist
  without that sibling checked out.
- **Shared `eslint`/`jest` config exports** — closing two gaps
  `mfe-pot-platform/CLAUDE.md` already documents as tribal knowledge every
  app repo has to independently remember (the React/a11y ESLint layer, and
  the `transformIgnorePatterns` fix for `@tn4consulting`-scoped ESM
  packages). Confirmed via a real migration + `nx lint`/`nx test` on
  `mfe-pot-dashboard-mfe` — identical results before/after.
  **`tsconfig.base.json` sharing does not work** in this family, discovered
  piloting it: Native Federation's build step (`@softarc/sheriff-core`,
  used for its dependency walk) throws once the extended base config lives
  in `node_modules` — every source file in the app is "outside of root"
  relative to that config's own directory. Every app repo builds through
  Native Federation, so this isn't `dashboard-mfe`-specific. The shared
  `configs/tsconfig.base.json` still ships as a documented reference (the
  canonical option list, including the `"types": ["node"]` fix), just not
  wired up via a real `extends` — each repo keeps its own inline copy.
- **`platform-critical`-labelled Renovate PRs get a CI backstop**: past a
  stated adoption window (see item 4 below), any open PR bumping this
  package or the singleton group fails CI on every other PR in that repo,
  until merged. Updates always arrive as an ordinary, reviewable Renovate
  PR — never a silent pull — this backstop just stops one from being
  silently ignored.

Distribution is the published-package model this family already uses for
everything else cross-repo (`libs/shared/*` → GitHub Packages →
`pnpm install` → Renovate-driven updates) — deliberately not a copied file
(that forks silently at 100-engineer scale) and not a sibling-checkout
dependency (that breaks the "every MFE is independently testable"
principle `mfe-pot-platform/CLAUDE.md` already commits to).

## 4. Breaking-change / deprecation protocol for `libs/shared/*`

- A major version bump to any federation-shared singleton package (`react`,
  `shared-ui-scds-core`, `shared-federation-runtime`) requires the platform
  team to open a tracking issue *before* publishing, tag every consumer
  team (via the ownership map), and give a stated adoption window.
- **That window is a concrete number of days, decided here: 14 days** from
  the Renovate PR opening in a given app repo to `check-platform-versions`'s
  `platform-critical` backstop (item 3) turning that repo's CI red. Chosen
  as long enough for a team's normal review cadence, short enough that a
  singleton drift doesn't sit for a sprint. Revisit if 14 days proves too
  tight or too loose once this has run for a while.
- Every `libs/shared/*` package gets a `CHANGELOG.md` (even a manually
  updated one) — no changelog convention exists today.
- Non-singleton shared packages (`auth`, `i18n`, `content-client`,
  `observability`, etc.) follow normal semver + Renovate, no special
  process — a version mismatch there is a build-time failure, caught
  immediately, not a silent runtime one.

## 5. CONTRIBUTING.md

One per app repo (short, repo-specific) plus a longer one in
`mfe-pot-platform` covering the shared-package contribution path. Each
states concretely:
- Required local checks before a PR: `nx run-many -t lint,test,build --all`
  and `pnpm run check:versions` (item 3).
- What CI already gates (lint/test/build, `kind` validation, `deploy-eks`),
  so a contributor doesn't re-derive what green CI already proves.
- How to consume a new `@tn4consulting/shared-*` version and where the
  authoritative version lives (`platform-versions.json`, not just "whatever
  Renovate proposes").
- Links out to `mfe-pot-platform/CLAUDE.md` (or, standalone, the synced
  `docs/PLATFORM_STANDARDS.md` from item 3) for architecture rationale
  rather than restating it.

## 6. PR review shape

- App-repo PRs: reviewed and merged autonomously by the owning team, no
  cross-team gate — that's the point of the repo split.
- `mfe-pot-platform` PRs touching the extra-scrutiny paths (item 2): same
  CODEOWNERS gate as today, plus a recommendation to broadcast non-trivial
  shared-package changes (new package, breaking change, sharing-policy
  change) via whatever cross-team channel the org already uses — no new
  chat infra invented here.

## 7. PR/issue templates

A minimal `.github/PULL_REQUEST_TEMPLATE.md` per repo: checklist for CI
green, `platform-versions.json`/`check:versions` checked if touching shared
deps, docs updated if behavior changed.

## Sequencing beyond this doc

Two more phases exist, but their *mechanics* are already tracked
elsewhere — this doc only assigns ownership under the new team structure,
it doesn't re-plan them:

- **AWS EKS rollout completion** (`TODO.md`'s "Hosting / CI" section,
  `docs/plans/20260808-1500-mfe-pot-aws-eks-terraform.md`) — Terraform
  cluster/foundation/bootstrap: platform team. Each app repo's own
  `values-eks.yaml`/Ingress-TLS/`deploy-eks` CI job: that repo's owning
  team, following the same pattern already landed in
  `mfe-pot-dashboard-mfe`. `mfe-pot/tools/deploy-eks.sh` cross-repo
  bring-up: platform team, mirroring `deploy-local.sh`'s existing home.
- **Remaining quality/observability backlog** (`TODO.md`): OpenTelemetry is
  already done (`shared-observability`/`shared-observability-server`,
  published and verified on both `kind` and EKS) — not open. What's left:
  Nx Remote Cache (platform team sets up the shared backend, each repo team
  points their own `nx.json` at it) and `apps/mfe-e2e`'s Phase 2 `webServer`
  rewire (platform team owns the composed suite, but it depends on every
  app team's repo layout — checkout path, serve port — staying stable).
  `docs/plans/20260808-1800-backend-outage-resilience.md`'s proof scope
  (`employment-insurance-mfe`/`-bff`) is a separate, not-yet-started design;
  once accepted, it's jointly owned by the employment-insurance team
  (BFF/frontend wiring) and the platform team (the two new shared
  `resilience-server`/`resilience-client` libs it proposes).
