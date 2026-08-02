# mfe-pot — sibling repo map

This folder is **not** a git repo and **not** a monorepo build root (no root package.json, no Nx/Turborepo/workspaces tying the children together). It's a plain filesystem grouping of independently-git-managed sibling clones that together make up the mfe-pot Government-of-Canada MFE proof-of-technology.

The project is **mid-split**: it started as a single Nx monorepo and is being carved into 6 repos. Full architecture rationale, non-negotiable requirements (bilingual, WCAG 2.2 AA, GCDS, Native Federation), and detailed gotchas live in **`mfe-pot-platform/CLAUDE.md`** — don't duplicate that here; read it directly when working on anything architectural. This file is just the map of *which repo is which* and how to navigate between them.

## The repos

| Repo | Role |
|---|---|
| `mfe-pot-platform` | The **platform repo** (formerly `mfe-app`, since renamed to match its `package.json` name and GitHub remote) — the original Nx workspace. Currently still contains full app source for all 5 apps (split in progress); once complete it becomes home to `libs/shared/*` (published as `@tn4consulting/shared-*` packages), the `client-profile-service` BFF, the composed `mfe-e2e` suite, Strapi, and `platform-versions.json` (cross-repo version-alignment source of truth). Has its own `CLAUDE.md` and `.claude/settings.json`. |
| `mfe-pot-shell` | New per-app repo. Host app, branded MSCA: app frame, GC header/footer, language switcher, mock sign-in, runtime federation manifest reader. |
| `mfe-pot-dashboard` | New per-app repo, + `benefit-aggregation-bff`. Cross-benefit overview, payment history, correspondence. |
| `mfe-pot-job-bank` | New per-app repo, + `job-bank-bff`. Job search and apply. |
| `mfe-pot-employment-insurance` | New per-app repo, + `employment-insurance-bff`. EI application, claim status, reporting. |
| `mfe-pot-employment-life-events` | New per-app repo. Guided "you lost your job" journey stitching the other three apps together. |
| `mfe-pot-renovate` | Shared Renovate config preset (`github>tn4consulting/mfe-pot-renovate`). Groups the Angular toolchain into one coordinated bump across repos, since there's no longer a pnpm workspace holding dependency versions in sync. **Not yet wired into the app repos** — deferred. |

None of these are git submodules — they're independent sibling clones, each with its own GitHub remote under `tn4consulting/`, deliberately kept that way (submodules don't play well with `git worktree add` / subagent worktree isolation, per `mfe-pot-platform/CLAUDE.md`).

This `mfe-pot` folder itself is a lightweight git repo (`git@github.com:tn4consulting/mfe-pot.git`) that tracks only the meta files at this level (this `CLAUDE.md`, `mfe-pot.code-workspace`) — every `mfe-pot-*` sibling folder is gitignored here since each already has its own independent `.git`/remote. It doesn't version-control the siblings' content, and it can't give you one commit spanning multiple sibling repos.

## Cross-repo mechanics worth knowing

- **No compile-time cross-repo safety net.** Version alignment (Angular/RxJS/GCDS/Node/TS) across the 6 repos is enforced by convention (`platform-versions.json` in `mfe-pot-platform`) and by Renovate grouping (`mfe-pot-renovate`), not by tooling — a Native Federation shared-singleton mismatch fails at runtime with no compile-time warning.
- **Local multi-repo dev happens via the VSCode multi-root workspace** `mfe-pot.code-workspace` (in this folder) — lists `mfe-pot-platform` plus the 5 per-app repos. `mfe-pot-renovate` isn't included (it's config, not app code). `canada.code-workspace` one level up is unrelated — it only covers `bdm-ado-*` folders.
- **Two separate `.claude` permission scopes**: this level (`mfe-pot/.claude/settings.local.json`) covers cross-cutting infra (kubectl, helm, pnpm, curl to the local job-bank host); `mfe-pot-platform/.claude/settings.json` is scoped to its own Nx build/lint/test workflow (`nx@nx-claude-plugins` plugin). They don't inherit into each other.
- **git commands are always scoped to whichever repo cwd resolves into** — there's no repo at the `mfe-pot` level itself, so e.g. `git status` run from here does nothing.
