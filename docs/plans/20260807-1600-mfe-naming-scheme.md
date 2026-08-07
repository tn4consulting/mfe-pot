# Ingress hostname scheme: front doors get plain names, remotes get -mfe

## Status (2026-08-07): done

Front-door URLs simplified to plain brand names; every internal federated remote suffixed `-mfe` throughout — Ingress host, repo/directory name, Nx project name, federation identity, Docker image, Helm chart/release. Follow-on to `20260807-1500-second-shell-host-proof-of-concept.md`, which first split the single shell into two host apps.

## Why

Once `mfe-pot-job-bank-shell` existed as a second host app, its natural front-door hostname collided in spirit with the `job-bank` remote it composes: `job-bank-shell.mfe-pot.local` (host) vs. `job-bank.mfe-pot.local` (remote) were distinct strings but easy to misread as the same thing. The fix settled on was to give front doors the plain, clean brand name a citizen would actually see (`msca.mfe-pot.local`, `job-bank.mfe-pot.local`) and push the disambiguating suffix onto the internal implementation detail — the federated remotes — since "this is an internal microfrontend, not the site itself" is exactly what `-mfe` communicates.

## What changed

**Ingress hostnames:**
| App | Role | Ingress host |
|---|---|---|
| `mfe-pot-msca-shell` | host | `msca.mfe-pot.local` |
| `mfe-pot-job-bank-shell` | host | `job-bank.mfe-pot.local` |
| `mfe-pot-job-bank-mfe` | remote | `job-bank-mfe.mfe-pot.local` |
| `mfe-pot-dashboard-mfe` | remote | `dashboard-mfe.mfe-pot.local` |
| `mfe-pot-employment-insurance-mfe` | remote | `employment-insurance-mfe.mfe-pot.local` |
| `mfe-pot-employment-life-events-mfe` | remote | `employment-life-events-mfe.mfe-pot.local` |

**Full identity cascade for each of the 4 remotes** (not just the hostname): local directory renamed (`mfe-pot-job-bank` → `mfe-pot-job-bank-mfe`, etc.), `apps/<name>` and `charts/<name>` directories renamed to match, `package.json`'s `name`, the Nx project's own `name` (its `tags`/`scope:*` deliberately **not** renamed — see below), `federation.config.mjs`'s `name` plus every `exposes` map path, Docker image tag, Helm chart `name`/release name/`frontend.name`/Ingress `metadata.name`, `.github/workflows/ci.yml`, each repo's own `tools/deploy-local.sh`, `jest.config.cts`'s `displayName`, `index.html`'s `<title>`, and `README.md`/`CLAUDE.md`. A genuinely easy-to-miss spot caught by an actual `docker build` failure the first time around (during the msca-shell rename) and checked explicitly this time: each Dockerfile's hardcoded `nx build <name>` command and `dist/apps/<name>/browser` copy path.

**Deliberately left un-suffixed** — these describe business-domain or UX identity, not hosting identity, and had no naming collision to disambiguate:
- Each BFF (`job-bank-bff`, `dashboard-bff`, `employment-insurance-bff`) — no naming collision exists for a BFF, and its in-cluster Service DNS name is what sibling BFFs already depend on (`dashboard-bff`'s `JOB_BANK_BFF_URL`/`EMPLOYMENT_INSURANCE_BFF_URL`).
- Nx `scope:*` dep-constraint tags and each `libs/data-access` library's own name (`job-bank-data-access`, etc.) — these model the *business domain* a lib belongs to, not which repo/hostname serves it; changing them would've required touching the app's own tag too just to keep `@nx/enforce-module-boundaries` happy, for zero benefit.
- CMS content-key namespaces (`job-bank.intro`, `dashboard.payment-history.*`, etc.) — same reasoning, domain identity.
- A host's own route paths (`/job-bank`, `/dashboard`, `/employment-insurance`, `/employment-life-events` in both shells' `routes.tsx`/`AppFrame.tsx`) — these are the shell's own user-facing URL paths, unrelated to which repo or federation-identity string composes that route.

**Consumers updated to match the renamed federation identity** (the string passed to `RemoteRouteHost`'s `remoteName=`, `loadRemoteModule()`'s first argument, and each host's `runtimeConfig.remotes` map key — as opposed to the route *path*, left alone per above):
- `mfe-pot-msca-shell`: `routes.tsx` (all `remoteName=`/`loadRemoteModule()` call sites), `main.tsx`'s dev-default `remotes` map, `charts/msca-shell/values.yaml`'s `runtimeConfig.remotes`.
- `mfe-pot-job-bank-shell`: same three spots, single `job-bank-mfe` entry.
- `mfe-pot-platform`: Strapi's seed script (`tools/cms/strapi/src/index.ts`)'s `REMOTES` array `name` fields (its `routePrefix` fields deliberately left as `/job-bank` etc. — see above), `charts/strapi/values.yaml`'s `REMOTE_*_URL` env var *names* (not just values) renamed to match (`REMOTE_JOB_BANK_URL` → `REMOTE_JOB_BANK_MFE_URL`, etc.), `mock-idp`'s `ALLOWED_REDIRECT_URI_ORIGINS` updated to the two hosts' new plain-name origins.
- Meta repo (`mfe-pot`): `tools/deploy-local.sh`'s `STEPS`/`STEP_RELEASES` arrays and persistence-check hostnames, `mfe-pot.code-workspace`, `README.md`, `CLAUDE.md` (including a new "Naming convention" bullet explaining this scheme for future reference), this `TODO.md`.

## What's proven

Per-repo `nx run-many -t lint,test,build --all` green and each affected Docker image builds, confirmed individually for all 4 renamed remotes and both shells before any cross-repo integration was attempted — the same discipline that caught the Dockerfile gotcha early this round instead of only at deploy time.

Full cross-repo integration then confirmed live on `kind`: every hostname serves, every remote's own `remoteEntry.json` reports its renamed federation identity (not just the URL it's served from), and both shells' injected `runtimeConfig.remotes` correctly key by the new names — checked directly against the deployed `env.js`, not assumed from the source.

**Two real bugs surfaced by attempting the actual redeploy, not caught by any individual repo's own verification:**
1. **Orphaned old-named Helm releases blocked the new ones.** The 4 renamed remotes' previous releases (`job-bank`, `dashboard`, `employment-insurance`, `employment-life-events`) were still deployed from before this change. Helm refused to let the new same-content releases (`job-bank-mfe`, etc.) claim resources — BFF ConfigMaps whose names didn't change, and one Ingress already using the new hostname from the prior hostname-only-rename session — since they were still ownership-tagged to the old release name. Fixed by uninstalling the 4 orphaned releases before retrying. Same class of issue as the `mfe-pot-shell`→`mfe-pot-msca-shell` rename's orphaned `shell` release, but this time it actively blocked the deploy instead of just lingering harmlessly.
2. **`mfe-pot-platform`'s own `tools/deploy-local.sh` never force-restarted `strapi`.** It force-restarts `mock-idp` after a rebuild (the standard fix for "static `:kind` tag + `pullPolicy: Never` gives Kubernetes no restart signal," documented everywhere else in this codebase) but was missing the identical restart call for `strapi`, a few lines above. This is a real, pre-existing gap — not introduced by this change — that happened to surface *because* this change touched `tools/cms/strapi/src/index.ts`: the rebuilt-and-loaded image sat completely unserved, and the running (2+-day-old) pod kept silently answering with the pre-rename `REMOTE_*_URL` names and stale remote-directory entries. Caught only because the live verification checked Strapi's actual `/api/remotes` output, not just that the hostname returned 200. Fixed in `tools/deploy-local.sh`; confirmed after the fix that Strapi's directory shows exactly the 4 renamed entries with no stale duplicates (its SQLite database resets fresh on pod restart, so no manual cleanup was needed once the pod actually restarted).

## Where the durable detail lives

The meta repo's own `../CLAUDE.md` ("Cross-repo mechanics worth knowing" → "Naming convention") is the living reference for this scheme going forward. Each renamed repo's own `CLAUDE.md` documents its specific `-mfe` identity and points back to the meta repo for the rationale.
