# mfe-pot: federation remote-loading integrity

## Status

Design only — not started. Elaborates `../TODO.md`'s "Federation remote-loading
integrity" item (scoped 2026-08-10), broadened from a same-family
self-published-hash design into a two-tier trust model after the requirement
was clarified: the design also needs to cover remotes from providers outside
this family's control (e.g. a province operating its own MFE and plugging it
into a shell we run), not only the four remotes we build ourselves.

## Context

`mfe-pot-msca-shell`'s and `mfe-pot-job-bank-shell`'s `main.tsx` are
byte-for-byte identical in the relevant logic (each carries its own inlined
copy — `main.tsx` runs before Native Federation's shared scope exists, so it
can't import `@tn4consulting/shared-*`, including the reusable
`shared-remote-registry` logic that has a fuller version of this same code).
`resolveFederationManifest()` fetches Strapi's `/api/remotes` with a 3s
timeout, falls back to `runtimeConfig.remotes` (dev defaults or a
Helm-ConfigMap-injected map) on failure, and produces a plain `name -> url`
map:

```ts
// apps/msca-shell/src/main.tsx (job-bank-shell: same shape)
interface StrapiRemoteAttributes { name: string; url: string; }
interface StrapiListResponse { data: StrapiRemoteAttributes[]; }
```

That map is handed straight to `initFederation()`, whose `loadRemoteModule`
result is threaded into `bootstrap()` and ultimately provided via
`RemoteModuleLoaderContext` (`shared-federation-runtime`) for
`RemoteRouteHost` and widget loaders to call. **No hash, signature, or
integrity field exists anywhere in this path today** — Strapi's `Remote`
content-type schema (`mfe-pot-platform/tools/cms/strapi/.../remote/schema.json`)
only carries `name`/`url`/`routePrefix`/`version`, and `remoteEntry.json`
itself (esbuild's Native Federation output) carries no hash of its own
`shared`/`exposes` entries either. A compromised Strapi entry or a MITM'd
`remoteEntry.json` response is effectively arbitrary code execution in the
shell's origin, since Native Federation fetches and evaluates that JS
directly (`RemoteRouteHost`'s `await loadRemoteModule(remoteName,
'./Component')`).

TODO.md originally scoped this as: each remote's CI emits a SHA-384 of its
own `remoteEntry.json`, publishes it alongside the Strapi manifest entry,
shells verify before load. That closes the gap **for remotes we build** —
the hash's trustworthiness rests on "we trust our own CI to compute an
honest hash and publish it over an authenticated channel," not on the
remote's own runtime claim about itself. It does not close the gap for a
remote built and operated by someone else: if the remote is the party
computing and publishing its own hash, a malicious or compromised
third-party remote just hashes its own malicious payload correctly. The
architecture explicitly supports composing remotes a host doesn't build
(`docs/architecture.md`'s "runtime federation only... loaded at runtime,
never compiled into a host" — that's precisely what would let a province's
MFE plug into `msca-shell` someday) — so a complete design needs a trust
model that covers that case, even though no such remote exists in the
family today.

## Two-tier trust model

**Tier 1 — first-party remotes** (`dashboard-mfe`, `job-bank-mfe`,
`employment-insurance-mfe`, `life-events-mfe`). We own the CI end to end.
Attacker model: MITM between a remote's real `remoteEntry.json` and the
shell (compromised Strapi entry, DNS/TLS-strip, compromised ingress/CDN) —
not the remote's own build process. Self-published SHA-384 + an
authenticated publish channel is sufficient, matching TODO.md's original
scope.

**Tier 2 — third-party provider remotes**. Not built by any repo in this
family; hypothetical/future (no real example exists yet — this tier is
designed ahead of need, the way `mfe-pot-job-bank-shell` proved the
multi-host pattern before a second real host existed). Attacker model
additionally includes the remote itself being malicious or compromised at
its source, so the remote cannot be the root of trust for its own integrity
claim. This needs three things a same-family design doesn't:

1. **A trust registry** — a platform-maintained allowlist of approved
   provider identities, each with a registered public key and expected
   origin, established through an out-of-band onboarding process (like
   registering an OAuth client), never self-service and never writable by
   the remote it describes.
2. **Signed manifests** — each release is signed by the provider's own
   private key; the shell verifies the signature against the *registered*
   public key (from the trust registry, not from anything the manifest
   fetch itself supplies) before trusting the declared hash(es), then
   verifies the fetched `remoteEntry.json`/chunks against those hashes.
   Signing the manifest (which itself references chunk hashes) is enough —
   no need for a second, separate signature per chunk.
3. **CSP as defense in depth** — a `script-src` origin allowlist scoped to
   registered provider origins, so a verification bug isn't the only thing
   standing between a compromised entry and code execution. Complementary
   to, not a replacement for, (1)/(2); out of scope for this doc's
   crypto-verification core but worth a follow-on item.

This is the same shape as existing prior art for "don't trust the mirror,
trust a small pinned root" — TUF (The Update Framework) and Sigstore/cosign
solve the same problem for package registries and container images
respectively. Nothing here proposes adopting either wholesale; the point is
the pattern (separate root of trust from content publisher), not the
specific tooling, given this family's PoC scale.

## Where the trust registry should *not* live

Strapi's existing `Remote` content type is the wrong place for Tier 2's
trust anchors. Today it has public `find`/`findOne` access
(`ensurePublicReadAccess(strapi, 'remote', ['find', 'findOne'])`) and is
seeded create-only from `mfe-pot-platform/tools/cms/strapi/src/index.ts`'s
hardcoded `REMOTES` array — a self-service directory of "here's where each
remote currently lives," not a security boundary. Reusing it as the store
for provider public keys would conflate the two: anyone who could get an
entry created (or, per the "no analogue to `deploy-eks.sh`'s seeding
pattern" finding — anyone who could influence the env vars a redeploy
seeds from) could effectively self-register as trusted.

Proposed instead, matching this family's existing PoC-scale conventions:
a committed file, `trusted-providers.json` in `mfe-pot-platform` (structurally
analogous to `platform-versions.json` — small, human-readable, one owning
repo) — the actual root of trust, auditable via PR review the same way any
other change to that repo is. Strapi can still mirror it into a read-only
content type for convenient runtime lookup by both shells, but the
mirrored copy is never the thing being trusted — the committed file is.
This deliberately avoids repeating `platform-versions.json`'s known failure
mode (manually-bumped, drifts silently — TODO.md documents it drifting for
real today) for the *hash-propagation* side of Tier 1: that's a separate,
already-flagged open question (see TODO.md's "Decide how the hash travels
... without becoming another manually-maintained cross-repo sync point").
For Tier 2's trust *registry* specifically, manual/reviewed changes are
actually the right call, not a shortcut — who to trust at all is a
human/policy decision, not something that should auto-sync from anywhere.

## Design: verification flow

**Tier 1 (self-published hash).**
1. Each first-party remote's CI computes SHA-384 of its built
   `remoteEntry.json` (and/or the `exposes` chunk files it references) as a
   build step.
2. The hash is published to Strapi's `Remote` entry for that remote, over
   an authenticated channel (a Strapi API token scoped to write access on
   `remote` — the public role today only has `find`/`findOne`; see
   "Open decisions" below on write-path mechanics). This closes the
   create-only-seed gap noted in research: the seed/update path needs to
   become an upsert of `url`+`version`+`hash` together, not a create-once.
3. Shell fetches the manifest (now `{ name, url, hash }` entries), fetches
   `remoteEntry.json`, recomputes its hash, compares. Mismatch → treat like
   any other remote-load failure (`RemoteErrorBoundary`'s existing
   "temporarily unavailable" fallback), never execute.

**Tier 2 (signed manifest + trust registry).**
1. Provider signs their `remoteEntry.json` (which itself lists chunk
   hashes) with their private key, out of band from this family's CI.
2. Provider's identity, public key, and expected origin are already present
   in `trusted-providers.json` from onboarding — not supplied at load time.
3. Shell fetches the manifest entry, looks up the claimed provider identity
   in the trust registry, verifies the signature against the *registered*
   key (never a key embedded in the fetched payload itself — that would let
   an attacker just supply their own key alongside their own signature).
4. On success, proceed as Tier 1 (hash-verify the fetched content against
   the now-trusted manifest); on any failure (unknown provider, bad
   signature, origin mismatch), refuse to load.

Both tiers converge on the same call site: verification wraps the raw
`loadRemoteModule` function *before* it's placed into
`RemoteModuleLoaderContext`, rather than living inside
`shared-federation-runtime`'s existing `RemoteRouteHost`. That's the one
place already common to both shells (per current research: `main.tsx` in
each shell obtains `loadRemoteModule` from `initFederation()`'s result, then
threads it into `bootstrap()`). Concretely, `shared-federation-runtime`
would grow a new export — something like `createVerifiedRemoteModuleLoader
(loadRemoteModule, registry)` — that both shells adopt in place of passing
the raw federation-result loader straight through. `RemoteRouteHost` and
the widget-loader path stay unchanged, since they already only depend on
`useRemoteModuleLoader()`'s black-box function type.

## Where new code would live (prospective — nothing built yet)

| What | Repo | Path |
|---|---|---|
| `trusted-providers.json` (Tier 2 root of trust) | `mfe-pot-platform` | repo root, alongside `platform-versions.json` |
| `hash`/`signature` fields on `Remote` content type; upsert (not create-only) seeding; authenticated write role | `mfe-pot-platform` | `tools/cms/strapi/src/api/remote/`, `tools/cms/strapi/src/index.ts` |
| `createVerifiedRemoteModuleLoader`, hash/signature-verification logic | `mfe-pot-platform` | `libs/shared/federation-runtime` (or a new `libs/shared/remote-integrity` if the crypto surface is big enough to warrant its own package) |
| CI step: compute + publish SHA-384 of built `remoteEntry.json` | `mfe-pot-dashboard-mfe`, `mfe-pot-job-bank-mfe`, `mfe-pot-employment-insurance-mfe`, `mfe-pot-life-events-mfe` | each `.github/workflows/ci.yml` |
| Adopt `createVerifiedRemoteModuleLoader` in place of the raw federation-result loader | `mfe-pot-msca-shell`, `mfe-pot-job-bank-shell` | each `apps/*-shell/src/main.tsx`/`bootstrap.tsx` |
| CSP `script-src` allowlist (defense in depth, Tier 2) | `mfe-pot-msca-shell`, `mfe-pot-job-bank-shell` | Ingress/Helm chart or a response-header middleware — exact mechanism not yet chosen |

## Recommended proof-of-concept scope, when picked up

Build Tier 1 first and prove it end to end on one remote (mirrors the
family's existing prove-then-generalize precedent —
`mfe-pot-job-bank-shell` proved the multi-host pattern before generalizing;
`docs/plans/20260808-1800-backend-outage-resilience.md` recommends the same
shape for its own scope). Tier 2 has no real consumer yet, so build it far
enough to be *demoable* — a synthetic "trusted provider" entry (a remote we
control, deliberately routed through the Tier 2 signature path instead of
Tier 1) proves the mechanism without needing an actual external partner.
Generalizing Tier 1 to all four remotes' CI, and finding/onboarding a real
Tier 2 provider, are both future work past this PoC pass.

## Open decisions, explicitly not resolved here

- **Signature algorithm** for Tier 2 — Ed25519 is the likely default
  (small keys/signatures, no parameter-choice footguns) but not decided.
- **Strapi write-path mechanics for Tier 1's hash** — API token scoped to
  `remote` write access is the sketch above; exact auth mechanism (Strapi
  API token vs. a small authenticated publish endpoint) not decided.
- **Key rotation/revocation** for a Tier 2 trusted provider — not designed;
  matters once a real provider exists, not before.
- **CSP header design/delivery mechanism** — flagged as complementary and
  necessary but intentionally not designed in this pass.
- **Whether Strapi's current public write-adjacent seeding behavior needs
  independent hardening** regardless of this design — related but separate
  from remote-loading integrity specifically.
