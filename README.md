# mfe-pot

> **Disclaimer:** This is an independent proof-of-technology project, built
> as a personal/consulting exploration of micro-frontend architecture. It is
> **not affiliated with, endorsed by, or associated with Service Canada,
> Employment and Social Development Canada (ESDC), or the Government of
> Canada** in any way. "MSCA" and any GC branding/design-system references
> are used only to ground the proof of technology in a realistic scenario.

Meta repo for the MSCA (My Service Canada Account) micro-frontend proof of
technology. It holds only cross-repo coordination files — the repo map below,
the VSCode multi-root workspace, and `TODO.md` — not any application code.
See `CLAUDE.md` for the full navigation notes this file summarizes.

## Architecture

The project split from a single Nx monorepo into **7 independent repos**:
two host ("shell") apps — `mfe-pot-msca-shell` and the minimal proof-of-
concept `mfe-pot-job-bank-shell`, proving the federation pattern
generalizes to more than one host — four benefit-domain frontends (each
with its own BFF), and this meta repo tying them together for local
multi-repo dev. All are federated at runtime via [Native Federation](https://www.npmjs.com/package/@softarc/native-federation) — each
host reads a runtime manifest and loads its remotes' entry points, so the
apps are independently deployable and are not built or versioned together.
Every app is **React** — the family started as a mixed Angular/React
federation experiment and was later converted wholesale to React, with
Angular removed entirely (see
`docs/plans/20260805-1200-angular-to-react-migration.md` for the full
history).

Non-negotiable requirements across every app repo: bilingual (EN/FR), WCAG
2.2 AA, and SCDS — a self-contained, in-house, MSCA-portal-styled design
system (`@tn4consulting/shared-ui-scds-core`), which replaced an earlier
GC-owned design-system wrapper (GCDS) once GCDS proved to be built for
static content pages, not an authenticated portal. Full architecture
rationale and detailed gotchas live in `mfe-pot-platform/CLAUDE.md` — read
that directly before working on anything architectural; this file only maps
*which repo is which*.

None of the sibling repos are git submodules. They're independent clones
under the `tn4consulting` GitHub org, each with its own remote, deliberately
kept that way — submodules don't play well with `git worktree add` /
subagent worktree isolation.

## The repos

| Repo | Role |
|---|---|
| [mfe-pot-platform](https://github.com/tn4consulting/mfe-pot-platform) | The platform repo (formerly `mfe-app`). Home to `libs/shared/*` (published as `@tn4consulting/shared-*` packages), the composed `mfe-e2e` suite, Strapi, `platform-versions.json` (cross-repo version-alignment source of truth), and the two Helm library charts. |
| [mfe-pot-msca-shell](https://github.com/tn4consulting/mfe-pot-msca-shell) | MSCA host app: app frame, GC header/footer, language switcher, mock sign-in, runtime federation manifest reader. Composes all 4 remotes. No BFF. |
| [mfe-pot-job-bank-shell](https://github.com/tn4consulting/mfe-pot-job-bank-shell) | Second, minimal proof-of-concept host — composes only job-bank-mfe's `./Component`, no sidebar nav. No BFF. |
| [mfe-pot-dashboard-mfe](https://github.com/tn4consulting/mfe-pot-dashboard-mfe) | + `dashboard-bff`. Cross-benefit overview, payment history, correspondence. |
| [mfe-pot-job-bank-mfe](https://github.com/tn4consulting/mfe-pot-job-bank-mfe) | + `job-bank-bff`. Job search and apply. |
| [mfe-pot-employment-insurance-mfe](https://github.com/tn4consulting/mfe-pot-employment-insurance-mfe) | + `employment-insurance-bff`. EI application, claim status, reporting. |
| [mfe-pot-employment-life-events-mfe](https://github.com/tn4consulting/mfe-pot-employment-life-events-mfe) | Guided "you lost your job" journey stitching the other three apps together. No BFF. |

## Getting started

This is the **"how do I actually run the whole family"** doc. For
architecture, rationale, and gotchas, see `mfe-pot-platform/CLAUDE.md`; for
a single app's own standalone run instructions (plain `nx serve`, no
containers), see that repo's own README.

### Prerequisites

- **[asdf](https://asdf-vm.com/)** with the `nodejs` plugin — each repo's
  `.tool-versions` pins the exact Node version (22.22.0; anything ≥ 22.12
  works, older 22.x versions fail on some build-time deps).
- **pnpm** — not asdf-managed, install globally or via `corepack enable`.
- **A GitHub personal access token with `read:packages` scope** — every app
  repo's Docker image build pulls `@tn4consulting/shared-*` packages from
  GitHub Packages. Export it as `NODE_AUTH_TOKEN`, or have the `gh` CLI
  authenticated (`gh auth token` works as a substitute).
- **Docker Desktop**, **[kind](https://kind.sigs.k8s.io/)**, **helm**, and
  **kubectl** — the whole family runs as containers on a local `kind`
  cluster; there's no non-containerized way to run more than one app at a
  time (a single app's own README covers running *that app alone* via
  `nx serve`, no containers needed).

### First-time setup

1. Clone this repo and all 6 app repos as **siblings** in one parent
   folder — this repo's own multi-root workspace file, and every app
   repo's `deploy-local.sh`, expect that exact layout:
   ```bash
   git clone git@github.com:tn4consulting/mfe-pot.git
   cd mfe-pot
   git clone git@github.com:tn4consulting/mfe-pot-platform.git
   git clone git@github.com:tn4consulting/mfe-pot-msca-shell.git
   git clone git@github.com:tn4consulting/mfe-pot-job-bank-shell.git
   git clone git@github.com:tn4consulting/mfe-pot-dashboard-mfe.git
   git clone git@github.com:tn4consulting/mfe-pot-job-bank-mfe.git
   git clone git@github.com:tn4consulting/mfe-pot-employment-insurance-mfe.git
   git clone git@github.com:tn4consulting/mfe-pot-employment-life-events-mfe.git
   ```
   The 4 remotes' GitHub repo names carry the `-mfe` suffix too (see
   `CLAUDE.md`'s "Naming convention" bullet) — same as the local directory
   name, no explicit target directory needed.
2. Open `mfe-pot.code-workspace` in VS Code for a multi-root view across
   all 7 repos.
3. Export your GitHub token: `export NODE_AUTH_TOKEN=<your token>`.
4. In `mfe-pot-platform`, install deps and sanity-check the build:
   ```bash
   cd mfe-pot-platform
   pnpm install
   nx run-many -t lint,test,build --all
   ```
5. In each of the 6 app repos, `pnpm install`.

### Running the whole stack on `kind`

Every app is deployed as a real container to a local `kind` cluster via
Helm — the same shape that ships to production (one image per app,
runtime-injected config, Ingress), not `nx serve`. Each repo's
`pnpm deploy:local` is idempotent — safe to rerun after a code change.

1. **Deploy Strapi first** (from `mfe-pot-platform`) — it creates/reuses
   the shared `kind` cluster (named `kind` by default; override with
   `CLUSTER_NAME` if you already use that name for something else) that
   every app repo below reuses, and installs `ingress-nginx`:
   ```bash
   cd mfe-pot-platform
   pnpm deploy:local
   ```
2. **Deploy each app repo**, in any order:
   ```bash
   cd ../mfe-pot-msca-shell                && pnpm deploy:local
   cd ../mfe-pot-job-bank-shell                 && pnpm deploy:local
   cd ../mfe-pot-dashboard-mfe                  && pnpm deploy:local
   cd ../mfe-pot-job-bank-mfe                   && pnpm deploy:local
   cd ../mfe-pot-employment-insurance-mfe       && pnpm deploy:local
   cd ../mfe-pot-employment-life-events-mfe     && pnpm deploy:local
   ```
   Each script builds that repo's image(s), loads them into `kind` (no
   registry round-trip), and `helm upgrade --install`s that repo's chart —
   it needs `mfe-pot-platform` checked out as a sibling for the Helm
   library-chart `file://` dependency and (for Strapi's own hostname) the
   shared `kind-config.yaml`.
3. **Add every app's hostname to `/etc/hosts`** (`kind` has no real DNS):
   ```
   127.0.0.1 cms.mfe-pot.local
   127.0.0.1 mock-idp.mfe-pot.local
   127.0.0.1 msca.mfe-pot.local
   127.0.0.1 job-bank.mfe-pot.local
   127.0.0.1 dashboard-mfe.mfe-pot.local
   127.0.0.1 job-bank-mfe.mfe-pot.local
   127.0.0.1 employment-insurance-mfe.mfe-pot.local
   127.0.0.1 employment-life-events-mfe.mfe-pot.local
   ```
   The two host apps ("front doors") keep plain brand names —
   `msca.mfe-pot.local`, `job-bank.mfe-pot.local` — while every internal
   federated remote gets an `-mfe` suffix, since `job-bank.mfe-pot.local`
   (the job-bank-shell host) and `job-bank-mfe.mfe-pot.local` (the job-bank
   remote it composes) would otherwise be one hyphen apart and easy to
   confuse.
4. Browse to `http://msca.mfe-pot.local` and sign in with the mock
   login, and separately to `http://job-bank.mfe-pot.local` to see
   the second, minimal host — same shared `mock-idp`, distinct branding —
   or verify any single app with curl, e.g.
   `curl -H "Host: job-bank-mfe.mfe-pot.local" http://localhost/`. First visit
   to `http://cms.mfe-pot.local/admin` prompts you to create the Strapi
   admin account (no default credentials are seeded).

### Iterating on one app without a full kind rebuild

Redeploying an app's image to `kind` on every code change is slow — fine for
verifying the whole family together, not for a tight edit/reload loop on one
app. Because remote discovery is a **live, Strapi-backed directory** (not a
file baked into the shell's build — see `mfe-pot-platform/CLAUDE.md`'s
"Federation" section), you can leave the rest of the family running on
`kind` and swap just the one app you're iterating on for a local dev server:

1. Leave the full `kind` stack up (steps above).
2. Run the app you're changing standalone instead of via its `kind` pod —
   e.g. `cd mfe-pot-job-bank-mfe && pnpm exec nx serve job-bank-mfe`
   (port 4203; see that repo's own README for its exact serve command/port).
   Its dev server sends `Access-Control-Allow-Origin: *`, so a `kind`-hosted
   shell can load it cross-origin with no extra config.
3. In the Strapi admin (`http://cms.mfe-pot.local/admin`), edit that app's
   `Remote` entry's URL to point at your local dev server (e.g.
   `http://localhost:4203/remoteEntry.json`) instead of its `kind` Ingress
   URL.
4. Reload the shell — `RemoteRegistryProvider` is polled per navigation, not
   cached at build time, so no shell rebuild/restart is needed. Point the
   Strapi entry back at the `kind` URL when you're done.

This only swaps a **routed remote** (a full app screen). A cross-remote
*widget* (e.g. dashboard's payment-history widget embedded in
employment-life-events) is loaded by whichever host mediates it, through the
same registry entry — the same swap works, just double-check which host
("shell") is doing the mediating for that particular widget (see the
platform repo's CLAUDE.md "Federation" section).

### Testing

Three tiers, cheapest/fastest first:

- **Per-app unit tests + lint** (Jest/ESLint), the tight inner loop for a
  single app — no `kind`, no sibling repos running: `pnpm exec nx test
  <app>` / `pnpm exec nx lint <app>` inside that app's own repo (see its
  README's "Test, lint, build" section). Across every repo at once:
  `nx run-many -t test --all` (run from each repo — there's no single
  workspace root that spans all 7).
- **One app's own standalone serve**, no shell/siblings required — every
  app is independently buildable/serveable/testable by design (see the
  platform repo's CLAUDE.md "Independent testability" section). Use this to
  verify an app's own behavior in isolation before checking it federated.
- **The full family on `kind`** (this doc's main walkthrough above) — the
  only way to exercise real cross-app behavior: routed federation across
  hostnames, cross-remote widget embedding, the BFF-backed golden path
  (apply for a job, apply for EI, see it land in the dashboard overview),
  the language-switch broadcast across independently-loaded remotes, and
  the real container/Ingress/Helm shape production uses. Use the "iterating
  on one app" workflow above to keep this loop fast while changing one app.
  `mfe-pot-platform`'s composed `apps/mfe-e2e` Playwright suite (routed
  federation, cross-remote widgets, the language broadcast, the BFF-backed
  golden path, and `@axe-core/playwright` WCAG 2.2 AA scans) automates most
  of this, but is **currently incomplete**: its `webServer` array starts
  nothing at all (`client-profile-service`, the one thing it used to start,
  has been removed — see `TODO.md`'s "Hosting / CI" section) — run it
  against an already-running stack (`kind`, or several apps' own `nx serve`)
  until Phase 2 lands.

### Publishing a `libs/shared/*` package

Only needed if you're changing a shared library and want app repos to pick
it up. See `mfe-pot-platform/CLAUDE.md`'s "Strong contracts between split
repos" section for the mechanism and a real gotcha to avoid.

## Where things live

- **Architecture rationale, requirements, gotchas** — `mfe-pot-platform/CLAUDE.md`
- **Outstanding cross-repo work** (hosting/CI, demo narrative, docs) — `TODO.md` in this folder
- **Project-wide planning/design docs** — `docs/plans/` in this folder (`mfe-pot-initial-design.md` for the original design, the polyrepo-split/K8s-hosting doc for that migration's history); platform-specific planning docs, if any, live in `mfe-pot-platform`'s own `docs/plans/` instead
- **Cross-repo technical config** (Renovate preset, `platform-versions.json`) — `mfe-pot-platform`, not here
- **Per-repo details** — each repo has its own `CLAUDE.md`
