# mfe-pot: federation remote-loading integrity

## Status

**Implemented.** Phase 1 (job-bank-mfe → job-bank-shell, proving the
mechanism end to end) and Phase 2 (generalizing to `dashboard-mfe`,
`employment-insurance-mfe`, `life-events-mfe`, and `msca-shell`, the
primary demo shell) are both live — all 4 remotes sign their federation
manifest in CI, both shells (`msca-shell`, `job-bank-shell`) verify before
loading. Everything below this point was rewritten post-implementation to
describe what was actually built, not the original design sketch — see
"History" at the bottom for how the design changed along the way.

## The problem this closes

`mfe-pot-msca-shell`'s and `mfe-pot-job-bank-shell`'s `main.tsx` fetch a
federation manifest (remote name → `remoteEntry.json` URL) from Strapi's
`/api/remotes` at runtime and, before this work, handed the URL straight to
Native Federation's `loadRemoteModule`, which fetches and evaluates that JS
directly. A compromised Strapi entry or a MITM'd `remoteEntry.json`
response was effectively arbitrary code execution in the shell's origin.

## What was built: one signature mechanism, not two tiers

The original design sketch (see "History" below) split this into a
same-family "Tier 1" (a self-published SHA-384 hash) and a hypothetical
third-party "Tier 2" (signed manifest + trust registry). That split didn't
survive contact with its own threat model: a hash that only travels over
an authenticated-Strapi-write channel doesn't defend against a compromised
Strapi entry — the very threat it was scoped to close, since an attacker
who can write to Strapi can write a matching hash too. **What's actually
built is one mechanism for every remote**, first-party or (hypothetically,
still no real example) third-party: a signed manifest, verified against a
trust registry that never travels over Strapi or any other network path
shared with the thing being verified. "First-party vs. third-party"
survives only as a property of *how a registry entry gets provisioned*
(automatic, our own CI-held key vs. manual, out-of-band vetting for an
external partner) — never a different runtime code path.

## The new library: `@tn4consulting/shared-remote-integrity`

Published from `mfe-pot-platform` (`libs/shared/remote-integrity`),
currently `0.3.0`. Not federation-shared (doesn't need to be — it only
ever runs inside a single shell's own bundle or a remote's own CI, never
across a federation boundary).

- `sha384Base64`, `verifyRemoteManifest`, `createVerifiedRemoteModuleLoader`
  — the verification primitives, `jose`-backed (RS256 — reuses the exact
  pattern already proven by `shared-auth-server`'s JWT verification and
  `mock-idp`'s key generation, rather than introducing a new crypto
  dependency).
- `bin/sign-remote-manifest.mjs` — the CI-side signing CLI. Reads a built
  `dist/apps/<app>/browser/`, SHA-384-hashes `remoteEntry.json` and
  *every* file its `exposes[]` list references (not just the manifest —
  `exposes` entries have plain, non-content-hashed filenames, so nothing
  else ties their bytes to the manifest's own hash), signs the resulting
  claims as a 30-day-bounded compact JWS, writes `remoteEntry.json.sig`
  alongside the manifest.
- `bin/sync-trusted-remotes.mjs` — copies this package's own bundled
  `trusted-remotes.json` into a consuming shell's working tree via a
  `postinstall` script (same mechanism `shared-platform-standards`'s
  `sync-platform-standards` already uses for `PLATFORM_STANDARDS.md`).
  This is *why* the trust registry lives inside this package rather than
  at `mfe-pot-platform`'s repo root next to `platform-versions.json`: it
  has to ship inside a shell's own build output, and `platform-versions.json`'s
  live-fetched-by-a-separate-CLI consumption model doesn't fit that.

## The trust registry

`libs/shared/remote-integrity/trusted-remotes.json` — the actual root of
trust, committed and PR-reviewed, never written by CI. All 4 remotes are
registered, each with an RSA public JWK, a `kid`, and — a real correction
made partway through implementation — `allowedOrigins: string[]`, not a
single `allowedOrigin: string`. The same signed image is legitimately
served from more than one origin (`http://X.mfe-pot.local` on kind,
`https://X.aws.tn4consulting.com` on EKS — one image built once and
promoted unchanged, per `mfe-pot-platform/CLAUDE.md`'s "Runtime config,
not build-time" section), so a single-origin field would have rejected
every real EKS deployment.

```json
{
  "version": 1,
  "remotes": {
    "job-bank-mfe": {
      "kid": "job-bank-mfe-2026",
      "publicKeyJwk": { "kty": "RSA", "n": "...", "e": "AQAB" },
      "alg": "RS256",
      "allowedOrigins": [
        "http://job-bank-mfe.mfe-pot.local",
        "https://job-bank-mfe.aws.tn4consulting.com"
      ],
      "provisioning": "first-party-ci"
    }
  }
}
```

`trusted-remotes.dev.json` (a separate file, `http://localhost:*` origins)
exists for local-dev entries but is currently empty and not wired to any
real dev keypair — see "Known gaps" below.

## Two stages, both required

Research during implementation surfaced that `initFederation()` itself
fetches every remote's `remoteEntry.json` up front to reconcile the
page-wide shared-singleton import map (`react`, `shared-ui-scds-core`,
`shared-federation-runtime`) — a tampered `shared[]` block there could in
principle hijack a shared singleton page-wide, before any
`loadRemoteModule` call happens. A `loadRemoteModule`-only wrapper misses
this entirely, so verification is split in two:

- **Stage A** (`main.tsx`, both shells) — `resolveFederationManifest`
  became `fetchCandidateManifest` + `verifyAndAdmitManifest`: for every
  Strapi-supplied (or fallback) candidate, fetch `remoteEntry.json` +
  sibling `.sig`, verify the signature, re-hash the fetched bytes, and
  only admit passing entries to `initFederation()`. Runs **before**
  `initFederation()` is called at all, which is why it can't use the
  published library — `main.tsx` runs before Native Federation's
  import-map/shared scope exists, so it can't import any bare specifier,
  workspace or third-party (confirmed against both shells' own `CLAUDE.md`,
  and against `apps/*/src/app/auth-flight.ts`'s existing precedent of
  hand-rolling `crypto.subtle` for PKCE rather than importing a library).
  Each shell carries its own hand-rolled, zero-import
  `verify-manifest-signature.ts` doing the identical RS256-via-`crypto.subtle`
  check the library does with `jose` — an accepted, tested-for-drift
  duplication, the same shape `resolveFederationManifest` itself already
  was (a hand-inlined copy of `shared-remote-registry`'s fuller logic).
- **Stage B** (`App.tsx`, both shells) — wraps the Context-provided
  `loadRemoteModule` with the real, published
  `createVerifiedRemoteModuleLoader`, so every
  `loadRemoteModule(remoteName, exposedModule)` call — both
  `RemoteRouteHost`'s routed remotes and, in `msca-shell`,
  `WIDGET_REGISTRY`-mediated cross-remote widget loading — hash-checks the
  specific exposed chunk against Stage A's already-verified claims before
  delegating to the real loader. Runs after `initFederation()`, so it has
  no bare-specifier constraint and uses the published library directly.

## The dev/Helm escape hatch

`nx serve`'s dev server never signs anything (only the Docker build does),
so unconditional strict verification would make every remote permanently
unloadable in local dev. `ShellRuntimeConfig.allowUnverifiedRemotes`
(`main.tsx`) follows the same runtime-config mechanism as everything else
in this family: `true` in `devDefaults` (nx serve), `false` explicitly in
each shell's Helm chart `values.yaml` for every real deployment — explicit
rather than omitted, since an absent key would silently inherit the dev
default in production too. `true` only ever logs a per-remote
`console.warn` and still loads the remote unverified; it never blocks —
blocking isn't this flag's job, unblocking local dev is.

## A real bug found building this, not a design decision

`docker/build-push-action`'s `secrets:` input is line-oriented (one
`key=value` pair per line). A genuinely multi-line value — a PEM private
key — gets silently truncated at its first embedded newline, which cost
two failed CI runs on `job-bank-mfe` before the real cause
(`ERR_OSSL_ASN1_NOT_ENOUGH_DATA`, `importPKCS8` choking on a key cut off
right after `-----BEGIN PRIVATE KEY-----`) showed up in the logs. Fixed by
writing the key to a runner-local temp file first and passing it via
`secret-files:` instead — every remote's `ci.yml` uses this from the
start now, not the broken form.

## Where the code actually lives

| What | Repo | Path |
|---|---|---|
| Verification library, signing/sync CLIs, trust registry | `mfe-pot-platform` | `libs/shared/remote-integrity` |
| `.sig` CORS fix | `mfe-pot-platform` + all 4 remotes | `tools/docker/nginx.conf` |
| Signing step (Dockerfile + CI) | all 4 remotes | `apps/<app>/Dockerfile`, `.github/workflows/ci.yml` |
| Stage A (`verify-manifest-signature.ts`, hand-rolled) | both shells | `apps/<shell>/src/verify-manifest-signature.ts` |
| Stage A wiring (verify-then-admit) | both shells | `apps/<shell>/src/main.tsx` |
| Stage B wiring (`createVerifiedRemoteModuleLoader`) | both shells | `apps/<shell>/src/app/App.tsx`, `src/bootstrap.tsx` |
| `allowUnverifiedRemotes: false` | both shells | `charts/<shell>/values.yaml` |

## Known gaps, not closed by this work

- **Local dev (`nx serve`) has no real signed path** — `allowUnverifiedRemotes`
  unblocks it by skipping verification entirely (warn-only), rather than
  a genuine dev-signing flow against `trusted-remotes.dev.json` (still
  empty). A follow-up, not solved here.
- **Double-fetch TOCTOU window in Stage B** — `createVerifiedRemoteModuleLoader`
  fetches a chunk once to hash it, then the real loader fetches it again.
  Small window, accepted at this project's scale; closing it would mean
  adopting es-module-shims' import-map `integrity` field (unconfirmed
  against this stack's pinned version) or a Service Worker interception
  layer.
- **Page-wide shared-singleton-hijack risk (Stage A's original motivation)**
  is architecturally plausible but not empirically proven against Native
  Federation's real reconciliation algorithm with a live tampered
  `shared[]` block — worth a dedicated test, not done as part of this pass.
- **Key rotation/revocation** — no process beyond "new keypair, new `kid`,
  PR to `trusted-remotes.json`, redeploy."
- **CSP `script-src` allowlist** — flagged as complementary defense in
  depth from the start, still untouched.
- **A real third-party (non-first-party) provider** — no such remote
  exists in the family; the single-mechanism design means onboarding one
  is just another registry row (a manually-vetted `publicKeyJwk` +
  `allowedOrigins`, `provisioning: "manual-partner-onboarding"`), not new
  code — but that's never been exercised against a real external party.

## History

Scoped 2026-08-10 as a same-family self-published-hash design (see git
history of this file for the original two-tier sketch — Tier 1 first-party
hash, Tier 2 hypothetical third-party signed manifest). Corrected
2026-08-11, in conversation, to the single-mechanism design described
above, once it became clear Tier 1's hash-only approach didn't actually
defend against its own stated threat (a compromised Strapi entry).
Implemented the same day: Phase 1 (job-bank-mfe/job-bank-shell) proved the
mechanism end to end on a real `kind` deployment before Phase 2 generalized
it to the other 3 remotes and `msca-shell`.
