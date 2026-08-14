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
| [mfe-pot-life-events-mfe](https://github.com/tn4consulting/mfe-pot-life-events-mfe) | Guided "you lost your job" journey stitching the other three apps together. No BFF. |

## Getting started

For architecture, rationale, and gotchas, see `mfe-pot-platform/CLAUDE.md`.
Setup instructions live in **`mfe-pot-platform/docs/`** rather than here,
since that's the one repo every setup path (dev machine, whole-family
`kind`, AWS EKS) already needs checked out:

- **[`mfe-pot-platform/docs/developer-setup.md`](mfe-pot-platform/docs/developer-setup.md)**
  — getting a dev machine ready to work in any one repo (editor, toolchain,
  lint/test/build loop). Start here.
- **[`mfe-pot-platform/docs/local-setup.md`](mfe-pot-platform/docs/local-setup.md)**
  — running the **whole mfe-pot family together**: first-time multi-repo
  clone/setup, the full `tools/deploy-local.sh` `kind`/Helm walkthrough
  (not `nx serve`), iterating on one app without a full rebuild, and testing
  tiers. This is the "how do I actually run this thing end to end" doc.
- **[`mfe-pot-platform/docs/eks-setup.md`](mfe-pot-platform/docs/eks-setup.md)**
  — hosting the family on AWS EKS for a live demo (Terraform layers,
  `tools/deploy-eks.sh`, teardown).

If you only care about one app in isolation (plain `nx serve`, no
containers), see that app's own README instead.

## Where things live

- **Living architecture reference** (system topology, request flows) — `docs/architecture.md`
- **Architecture rationale, requirements, gotchas** — `mfe-pot-platform/CLAUDE.md`
- **Setup guides** (dev machine, local `kind`, AWS EKS) — `mfe-pot-platform/docs/`
- **Outstanding cross-repo work** (hosting/CI, demo narrative, docs) — `TODO.md` in this folder
- **Project-wide planning/design docs** — `docs/plans/` in this folder (`mfe-pot-initial-design.md` for the original design, the polyrepo-split/K8s-hosting doc for that migration's history); platform-specific planning docs, if any, live in `mfe-pot-platform`'s own `docs/plans/` instead
- **Cross-repo technical config** (Renovate preset, `platform-versions.json`) — `mfe-pot-platform`, not here
- **Per-repo details** — each repo has its own `CLAUDE.md`
