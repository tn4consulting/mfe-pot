# mfe-pot — sibling repo map

This folder is a lightweight git repo (`git@github.com:tn4consulting/mfe-pot.git`) holding only meta files — it is **not** a monorepo build root (no root package.json, no Nx/Turborepo/workspaces tying the children together). The `mfe-pot-*` sibling folders inside it are independently-git-managed clones, not part of this repo's own history (see "This repo's own scope" below).

The project **finished its split** from a single Nx monorepo into 6 repos — all 5 frontends are extracted, each into its own repo with its own Dockerfile(s) and Helm chart. What's left (per-repo CI, AKS/ACR, demo narrative, docs) is tracked in `TODO.md` in this folder, not per-sibling. Full architecture rationale, non-negotiable requirements (bilingual, WCAG 2.2 AA, GCDS, Native Federation), and detailed gotchas live in **`mfe-pot-platform/CLAUDE.md`** — don't duplicate that here; read it directly when working on anything architectural. This file is just the map of *which repo is which* and how to navigate between them. Every repo, including this one, has its own `CLAUDE.md`; the 5 per-app repos' files point back to `mfe-pot-platform/CLAUDE.md` for shared rationale rather than duplicating it.

## The repos

| Repo | Role |
|---|---|
| `mfe-pot-platform` | The **platform repo** (formerly `mfe-app`, since renamed to match its `package.json` name and GitHub remote). Home to `libs/shared/*` (published as `@tn4consulting/shared-*` packages), the `client-profile-service` BFF, the composed `mfe-e2e` suite, Strapi, `platform-versions.json` (cross-repo version-alignment source of truth), and the two Helm library charts. Has its own `CLAUDE.md` and `.claude/settings.json`. |
| `mfe-pot-shell` | Host app, branded MSCA: app frame, GC header/footer, language switcher, mock sign-in, runtime federation manifest reader. No BFF. |
| `mfe-pot-dashboard` | + `dashboard-bff`. Cross-benefit overview, payment history, correspondence. |
| `mfe-pot-job-bank` | + `job-bank-bff`. Job search and apply. |
| `mfe-pot-employment-insurance` | + `employment-insurance-bff`. EI application, claim status, reporting. |
| `mfe-pot-employment-life-events` | Guided "you lost your job" journey stitching the other three apps together. No BFF. |

None of these are git submodules — they're independent sibling clones, each with its own GitHub remote under `tn4consulting/`, deliberately kept that way (submodules don't play well with `git worktree add` / subagent worktree isolation, per `mfe-pot-platform/CLAUDE.md`).

## This repo's own scope

`mfe-pot`'s own git history tracks only the meta files at this level (this `CLAUDE.md`, `README.md`, `mfe-pot.code-workspace`, `TODO.md`, and `docs/`) — every `mfe-pot-*` sibling folder is gitignored here since each already has its own independent `.git`/remote. It doesn't version-control the siblings' content, and it can't give you one commit spanning multiple sibling repos. `git` commands from this folder operate on this meta repo specifically, not on any sibling.

Cross-repo shared *technical* config (Renovate preset, `platform-versions.json`, and similar) lives in **`mfe-pot-platform`**, not here — see its own `CLAUDE.md`. This repo stays limited to non-code, filesystem-level coordination: the repo map, the VSCode workspace file, the cross-repo `TODO.md`, and `docs/plans/` (project-wide planning/design docs — see `mfe-pot-platform/CLAUDE.md`'s "Planning documents" section; a doc scoped to one repo alone can live in that repo's own `docs/plans/` instead) — project tracking and cross-cutting docs naturally belong at the level that sits above all 6 repos, not pinned inside whichever one happened to own them historically. `docs/msca-screenshots/` (reference screenshots of the real MSCA site, used for design fidelity — see `mfe-pot-platform/CLAUDE.md`'s "Design/UX fidelity" section) is gitignored here, same as it was in `mfe-pot-platform` before the move — local-only reference material, never pushed.

## Cross-repo mechanics worth knowing

- **No compile-time cross-repo safety net.** Version alignment (Angular/RxJS/GCDS/Node/TS) across the 6 app repos is enforced by convention (`platform-versions.json` in `mfe-pot-platform`) and by Renovate grouping (`default.json`, also in `mfe-pot-platform`), not by tooling — a Native Federation shared-singleton mismatch fails at runtime with no compile-time warning.
- **Local multi-repo dev happens via the VSCode multi-root workspace** `mfe-pot.code-workspace` (in this folder) — lists `mfe-pot-platform` plus the 5 per-app repos. `canada.code-workspace` one level up is unrelated — it only covers `bdm-ado-*` folders.
- **Two separate `.claude` permission scopes**: this level (`mfe-pot/.claude/settings.local.json`) covers cross-cutting infra (kubectl, helm, pnpm, curl to the local job-bank host); `mfe-pot-platform/.claude/settings.json` is scoped to its own Nx build/lint/test workflow (`nx@nx-claude-plugins` plugin). They don't inherit into each other.
- **git commands are always scoped to whichever repo cwd resolves into** — this folder's own repo is meta-only (see "This repo's own scope" above); a sibling's actual app code is only reachable by cd'ing into that sibling.
