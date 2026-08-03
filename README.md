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

The project split from a single Nx monorepo into **6 independent repos**:
one host ("shell") app, four benefit-domain frontends (each with its own
BFF), and this meta repo tying them together for local multi-repo dev. All
are federated at runtime via [Native Federation](https://www.npmjs.com/package/@angular-architects/native-federation) — the shell reads a
runtime manifest and loads each app's remote entry, so the apps are
independently deployable and are not built or versioned together.

Non-negotiable requirements across every app repo: bilingual (EN/FR), WCAG
2.2 AA, and the [GC Design System](https://design-system.alpha.canada.ca/) (GCDS). Full architecture rationale and
detailed gotchas live in `mfe-pot-platform/CLAUDE.md` — read that directly
before working on anything architectural; this file only maps *which repo is
which*.

None of the sibling repos are git submodules. They're independent clones
under the `tn4consulting` GitHub org, each with its own remote, deliberately
kept that way — submodules don't play well with `git worktree add` /
subagent worktree isolation.

## The repos

| Repo | Role |
|---|---|
| [mfe-pot-platform](https://github.com/tn4consulting/mfe-pot-platform) | The platform repo (formerly `mfe-app`). Home to `libs/shared/*` (published as `@tn4consulting/shared-*` packages), the `client-profile-service` BFF, the composed `mfe-e2e` suite, Strapi, `platform-versions.json` (cross-repo version-alignment source of truth), and the two Helm library charts. |
| [mfe-pot-shell](https://github.com/tn4consulting/mfe-pot-shell) | Host app: app frame, GC header/footer, language switcher, mock sign-in, runtime federation manifest reader. No BFF. |
| [mfe-pot-dashboard](https://github.com/tn4consulting/mfe-pot-dashboard) | + `dashboard-bff`. Cross-benefit overview, payment history, correspondence. |
| [mfe-pot-job-bank](https://github.com/tn4consulting/mfe-pot-job-bank) | + `job-bank-bff`. Job search and apply. |
| [mfe-pot-employment-insurance](https://github.com/tn4consulting/mfe-pot-employment-insurance) | + `employment-insurance-bff`. EI application, claim status, reporting. |
| [mfe-pot-employment-life-events](https://github.com/tn4consulting/mfe-pot-employment-life-events) | Guided "you lost your job" journey stitching the other three apps together. No BFF. |

## Local dev

Clone each sibling repo alongside this one (as `mfe-pot-<name>`), then open
`mfe-pot.code-workspace` in VSCode for a multi-root workspace covering the
platform repo plus all 5 app repos.

## Where things live

- **Architecture rationale, requirements, gotchas** — `mfe-pot-platform/CLAUDE.md`
- **Outstanding cross-repo work** (hosting/CI, demo narrative, docs) — `TODO.md` in this folder
- **Cross-repo technical config** (Renovate preset, `platform-versions.json`) — `mfe-pot-platform`, not here
- **Per-repo details** — each repo has its own `CLAUDE.md`
