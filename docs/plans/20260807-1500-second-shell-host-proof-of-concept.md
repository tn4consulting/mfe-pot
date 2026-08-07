# Prove the federation pattern generalizes: a second host app

## Status (2026-08-07): done

`mfe-pot-shell` renamed to `mfe-pot-msca-shell` in place (same git history, every internal identifier cascaded). A new sibling repo, `mfe-pot-job-bank-shell`, scaffolded from it as a second, minimal host app. Both verified independently (`nx run-many -t lint,test,build --all` green in each) and via a live `kind` deployment of both simultaneously against one shared `mock-idp`/Strapi.

## Why

Up to this point the family had exactly one host/shell app. That's proof that Native Federation can compose several remotes behind one branded front door — it's not yet proof that the *pattern itself* (a thin host, runtime remote discovery, shared federation singletons, host-mediated widget composition) generalizes to more than one host sharing the same platform infra. In the real world, Job Bank and MSCA genuinely are separate government sites with separate front doors that happen to share underlying services — this mirrors that shape and closes the gap.

## What changed

**`mfe-pot-shell` → `mfe-pot-msca-shell`** (in place — directory renamed, git history intact): every internal identifier cascaded to match — Nx project name, federation name (`federation.config.mjs`), PKCE `CLIENT_ID`, Docker image tag, Helm chart/release/Ingress names, `.github/workflows/ci.yml`, this app's own `tools/deploy-local.sh`. Behavior and scope are unchanged — it still composes all 4 remotes (dashboard, job-bank, employment-insurance, employment-life-events) exactly as before.

**New repo `mfe-pot-job-bank-shell`**: scaffolded from the renamed `mfe-pot-msca-shell` (same PKCE login flow, same Strapi-first-with-fallback federation-manifest resolution in `main.tsx`, same Helm chart shape) and then deliberately trimmed to the minimum needed to prove a second host works:
- Composes exactly **one** remote — job-bank's own routed `./Component` — via a plain `<RemoteRouteHost remoteName="job-bank" />`. No cross-remote widget-loader Contexts (`JobApplicationsWidgetLoaderContext` etc.) — this host never composes a widget from a second remote.
- **No sidebar nav.** `AppFrame.tsx` renders just `scds-header`/`scds-footer`; with exactly one destination, a collapsible nav sidebar would be pure decoration. `mfe-pot-msca-shell`'s `AppFrame.tsx` remains the reference if this host ever grows a second remote.
- Distinct identity end to end: Nx project `job-bank-shell`, federation name `job-bank-shell`, PKCE `CLIENT_ID = 'mfe-pot-job-bank-shell'`, dev-server port 4205 (so both hosts run side by side locally without colliding with `msca-shell`'s 4200), Ingress host `job-bank-shell.mfe-pot.local`, Helm release `job-bank-shell`.
- Job-Bank branding: `app-title="Job Bank"`, Job-Bank-flavored i18n copy (`login.heading: "Sign in to Job Bank"`), post-login navigation to `/job-bank` instead of `/dashboard`.

**`mfe-pot-platform`**: one functional change — `charts/mock-idp/values.yaml`'s `ALLOWED_REDIRECT_URI_ORIGINS` (comma-separated, per `apps/mock-idp/src/config.ts`) now lists both hosts' origins instead of the single old `shell.mfe-pot.local`. Everything else in the platform repo (`shared-federation-config`, the two Helm library charts, `platform-versions.json`, the Renovate preset) needed **zero** changes — confirmed by direct inspection, it was already fully host-count-agnostic. A few stale prose comments referencing the old single-shell assumption were also fixed for accuracy (`libs/shared/runtime-config`, `apps/mock-idp`).

**`mfe-pot-job-bank`** (the existing remote-only repo) needed **zero** changes — confirmed via full-repo grep that nothing in it hardcodes "shell" as an allowed consumer (`job-bank-bff`'s CORS is wide-open `cors()`, no origin allowlist), and its `federation.config.mjs` has no `remotes` key to update. It simply gained a second consumer.

**Meta repo (`mfe-pot`)**: `tools/deploy-local.sh` (`STEPS`/`STEP_BACKENDS`/`STEP_RELEASES` arrays, both hosts deployed last since they're frontend-only), `mfe-pot.code-workspace`, `README.md`, `CLAUDE.md`, and `TODO.md`'s handful of path references all updated for the rename and the 6→7 repo count.

## What's proven

The pattern mechanically works for a second, independently-branded, independently-deployed host app sharing the platform's infra (`mock-idp`, Strapi, the federation-shared singletons — `react`/`react-dom`/`@tn4consulting/shared-ui-scds-core`/`shared-federation-runtime`) with the original host. Verified concretely:
- `nx run-many -t lint,test,build --all` green in both `mfe-pot-msca-shell` and `mfe-pot-job-bank-shell` independently.
- Both Helm charts render with fully consistent, non-colliding resource names (`helm template`).
- Both deployed simultaneously to one local `kind` cluster, both reachable at their own Ingress hostnames, both able to complete PKCE sign-in against the one shared `mock-idp`.

## What's not yet proven

- **Sustained concurrent load** against one shared `mock-idp`/Strapi from two hosts — only exercised with light manual/CI traffic so far.
- **A host composing more than one remote while staying a minimal-scope PoC** — `job-bank-shell` deliberately stayed single-remote to keep this proof narrow; a host that needs both a sidebar nav *and* a second remote would need to bring back more of `mfe-pot-msca-shell`'s `AppFrame.tsx`/`routes.tsx` structure, not just extend the trimmed version.
- **A GitHub-side rename/repo-creation flow** — this doc covers the local/filesystem-level rename and scaffold only. `mfe-pot-shell` → `mfe-pot-msca-shell` on GitHub, and creating `mfe-pot-job-bank-shell` as a real GitHub repo, are deliberately left to be done separately (git history and remote URLs are unaffected either way, since GitHub's own repo rename auto-redirects the old clone URL — the same mechanism already proven for `mfe-app` → `mfe-pot-platform`).

## Where the durable detail lives

`mfe-pot-msca-shell/CLAUDE.md` and `mfe-pot-job-bank-shell/CLAUDE.md` (the latter's "What's deliberately different from mfe-pot-msca-shell" section specifically) are the living reference for how these two repos differ day to day. This doc captures the narrative and the decisions.
