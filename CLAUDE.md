# mfe-pot — sibling repo map

This folder is a lightweight git repo (`git@github.com:tn4consulting/mfe-pot.git`) holding only meta files — it is **not** a monorepo build root (no root package.json, no Nx/Turborepo/workspaces tying the children together). The `mfe-pot-*` sibling folders inside it are independently-git-managed clones, not part of this repo's own history (see "This repo's own scope" below).

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

None of these are git submodules — they're independent sibling clones, each with its own GitHub remote under `tn4consulting/`, deliberately kept that way (submodules don't play well with `git worktree add` / subagent worktree isolation, per `mfe-pot-platform/CLAUDE.md`).

## This repo's own scope

`mfe-pot`'s own git history tracks only the meta files at this level (this `CLAUDE.md`, `mfe-pot.code-workspace`, `default.json` — see "Renovate preset" below) — every `mfe-pot-*` sibling folder is gitignored here since each already has its own independent `.git`/remote. It doesn't version-control the siblings' content, and it can't give you one commit spanning multiple sibling repos. `git` commands from this folder operate on this meta repo specifically, not on any sibling.

## Renovate preset

`default.json` at this repo's root is the shared Renovate config preset for the whole mfe-pot family — originally lived in a separate `mfe-pot-renovate` repo, consolidated here since there was no technical reason to keep it apart (Renovate's bare `extends` convention just needs a `default.json` at a repo's root, and this repo is already the natural "shared config that spans all the app repos" layer). Groups `@angular/*`, `@angular-devkit/*`, `@schematics/angular`, and `listr2` into one coordinated bump (`rangeStrategy: pin`) — mirrors the `pnpm.overrides` block each app repo carries, since there's no longer a pnpm workspace holding these versions in sync across repos. Each app repo's `renovate.json` should be:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>tn4consulting/mfe-pot"]
}
```

**Not yet wired into the app repos** — deferred, same as before the consolidation. The old `mfe-pot-renovate` GitHub repo has been deleted.

## Cross-repo mechanics worth knowing

- **No compile-time cross-repo safety net.** Version alignment (Angular/RxJS/GCDS/Node/TS) across the 6 app repos is enforced by convention (`platform-versions.json` in `mfe-pot-platform`) and by Renovate grouping (this repo's `default.json`), not by tooling — a Native Federation shared-singleton mismatch fails at runtime with no compile-time warning.
- **Local multi-repo dev happens via the VSCode multi-root workspace** `mfe-pot.code-workspace` (in this folder) — lists `mfe-pot-platform` plus the 5 per-app repos. `canada.code-workspace` one level up is unrelated — it only covers `bdm-ado-*` folders.
- **Two separate `.claude` permission scopes**: this level (`mfe-pot/.claude/settings.local.json`) covers cross-cutting infra (kubectl, helm, pnpm, curl to the local job-bank host); `mfe-pot-platform/.claude/settings.json` is scoped to its own Nx build/lint/test workflow (`nx@nx-claude-plugins` plugin). They don't inherit into each other.
- **git commands are always scoped to whichever repo cwd resolves into** — this folder's own repo is meta-only (see "This repo's own scope" above); a sibling's actual app code is only reachable by cd'ing into that sibling.
