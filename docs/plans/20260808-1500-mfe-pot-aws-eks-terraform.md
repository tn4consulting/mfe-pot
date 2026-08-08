# mfe-pot: AWS EKS hosting via Terraform

## Status

Applied to a real AWS account (`147318891438`, `ca-central-1`) and verified
end to end: `mock-idp` and `job-bank-mfe` both manually built, pushed to ECR,
and deployed, confirmed serving over real HTTPS with a cert-manager-issued
cert, correct DNS (Route 53 + external-dns), and working cross-service
connectivity (Redis, mock-idp JWKS). All 8 chart-owning repos have
`values-eks.yaml`/Ingress-TLS/`deploy-eks` CI support committed and pushed.
GitHub Actions CI is wired with the 3 required repo variables plus
`NPM_READ_TOKEN` (fixing a separate, pre-existing GitHub Packages 403 that
predated this work).

**Real gotcha hit and fixed**: the GitHub Actions OIDC `sub` claim this org's
tokens actually carry is `repo:tn4consulting@<owner_id>/<repo>@<repo_id>:ref:refs/heads/main`
— not the classic `repo:ORG/REPO:ref:refs/heads/BRANCH` format most
AWS/GitHub OIDC tutorials show. Confirmed by decoding a real token via a
temporary debug step. `foundation/github_oidc.tf`'s trust policy condition
now wildcards both numeric IDs (`repo:tn4consulting@*/mfe-pot-*@*:ref:refs/heads/main`)
to match. If OIDC AssumeRoleWithWebIdentity ever silently fails again with
"Not authorized" despite a seemingly-correct trust policy, decode the actual
token first (`curl` the `ACTIONS_ID_TOKEN_REQUEST_URL` from within a step
with `id-token: write`) rather than assuming the classic claim format.

**Real gotcha hit and fixed**: EKS's own default node security group
(`terraform-aws-modules/eks`) only opens specific known ports (kubelet,
coredns, webhooks, node-initiated ephemeral 1025-65535 return traffic) — NOT
arbitrary pod-to-pod traffic on ports below 1024. Confirmed live:
ingress-nginx timed out reaching a frontend pod's port 80 on a different
node, while the same request to a BFF on port 3001 (inside the ephemeral
range) worked. Fixed with an explicit `node_security_group_additional_rules`
self-referencing allow-all rule in `cluster/eks.tf` — a standard requirement
for any real multi-node EKS + VPC CNI cluster, not optional hardening.

## Context

mfe-pot's hosting story is fully proven on a local `kind` cluster: 11 Docker
images (6 frontends, 3 BFFs, mock-idp, strapi), a Helm chart per app built on
two shared library charts (`mfe-frontend-lib`/`mfe-backend-lib`, in
`mfe-pot-platform`), and a "Stage 1" CI job in every app repo that builds
images and validates them against an ephemeral kind cluster. Every prior
planning doc (`TODO.md`, `mfe-pot-platform/CLAUDE.md`,
`20260801-1935-mfe-pot-polyrepo-split-and-k8s-hosting.md`) describes the
intended cloud target as **Azure (AKS + ACR)**, and explicitly recommended a
small checked-in `az` CLI script over a real Terraform/Bicep setup given the
project's PoC scale.

This doc overrides both of those, deliberately: hosting moves to **AWS EKS**
instead of Azure (no technical reason — the Azure account in question is
unmanageable), and this pass uses real infrastructure-as-code (**Terraform**),
not a CLI script, because that's what was actually asked for. This fills the
"Stage 2" gap every app repo's CI has left open since the kind-only pattern
was built.

**Corrected scope**: the "5 hostnames" language in older docs is stale. There
were **8** public Ingress hosts as of this doc's authoring — confirmed by
reading every chart's `templates/ingress.yaml`: `msca-shell`, `job-bank-shell`,
`dashboard-mfe`, `job-bank-mfe`, `employment-insurance-mfe`,
`employment-life-events-mfe`, `cms` (Strapi), and `mock-idp` (it has its own
Ingress too — a real browser-reachable `/authorize` redirect target). All 8
need the same TLS/DNS treatment. **Now 10**: the OpenTelemetry observability
pass (see `mfe-pot-platform/CLAUDE.md`'s observability section) added
`grafana` and `otel` as two more bare-upstream-image, Ingress-exposed charts
following this exact same `values-eks.yaml`/TLS-block pattern — `mfe-pot/tools/deploy-eks.sh`
deploys and verifies both alongside `session-cache`.

## Decisions

- **IaC tool**: Terraform, using `terraform-aws-modules/vpc` and `.../eks`
  rather than hand-rolled resources for the parts that have a mature module.
- **Region**: `ca-central-1`.
- **Domain**: `aws.tn4consulting.com` — a Route 53 public hosted zone is
  created for exactly this name; NS delegation from wherever the parent zone
  (`tn4consulting.com`) lives is a manual, one-time step outside Terraform.
- **Cost posture**: this is an occasional-demo PoC, not always-on. Terraform
  is split into **two state layers** — a persistent `foundation/` (state
  bucket, ECR, Route 53 zone, GitHub OIDC/IAM) that's essentially never
  destroyed, and an ephemeral `cluster/` (VPC, EKS, node group, addons) that
  gets `apply`'d before a demo and `destroy`'d after.
- **Ingress**: ingress-nginx behind an AWS NLB — not the AWS Load Balancer
  Controller/ALB — so every existing app repo's `templates/ingress.yaml`
  (`ingressClassName: nginx`) works completely unchanged.
- **AWS credentials**: the dev environment this was authored in has an
  invalid/expired token (`aws sts get-caller-identity` fails). Nothing gets
  applied until that's fixed and confirmed working.
- **Session cache**: keep the existing self-hosted in-cluster Redis
  (`mfe-pot-platform/charts/session-cache`) as-is. No ElastiCache in this
  pass.

## Where the code lives

| What | Repo | Path |
|---|---|---|
| All Terraform | `mfe-pot-platform` | `infra/terraform/{bootstrap,foundation,cluster}/` |
| `values-eks.yaml` + Ingress TLS block | each of the 6 app repos, plus `mfe-pot-platform`'s `mock-idp`/`strapi` charts | `charts/<name>/values-eks.yaml`, `charts/<name>/templates/ingress.yaml` |
| Stage 2 `deploy-eks` CI job | same 8 chart-owning repos | `.github/workflows/ci.yml` (new job on the 6 app repos with existing CI; a net-new workflow for `mfe-pot-platform`'s mock-idp/strapi) |
| Cross-repo orchestration script | `mfe-pot` (this meta repo) | `tools/deploy-eks.sh` — pure delegation, same convention as `tools/deploy-local.sh` |

Terraform itself lives in `mfe-pot-platform` because it's cross-repo
*technical* config (same reasoning as `platform-versions.json` and the Helm
library charts) — this meta repo stays pure filesystem-level orchestration,
per its own `CLAUDE.md`.

## Terraform layout

```
mfe-pot-platform/infra/terraform/
  bootstrap/    # one-time, LOCAL state, run by hand once: creates the S3 state bucket
  foundation/   # remote state, persistent layer
  cluster/      # remote state, ephemeral layer (terraform_remote_state reads foundation)
```

State backend: S3 native locking (`use_lockfile = true`) rather than a
DynamoDB lock table — one fewer persistent resource for the same guarantee.
No separate `modules/` directory — each of the VPC/EKS/IAM-IRSA upstream
modules is instantiated exactly once, so wrapping them in bespoke local
modules would add indirection with no reuse payoff.

### `foundation/` (persistent — never destroyed on the demo cycle)

- **ECR**: one repository per image (`for_each` over 11 names matching
  today's local Docker image names exactly), `scan_on_push`, immutable tags,
  and a lifecycle policy (keep ~15 most recent tagged images, expire
  untagged after 7 days).
  - Pushing the two Helm library charts as ECR OCI repos is **explicitly out
    of scope** for this pass — the existing sibling-`file://` Chart.yaml
    dependency already works unchanged in a GitHub Actions runner (same
    sibling-checkout trick Stage 1's `kind-validation` job already uses), so
    nothing about reaching EKS blocks on it. Standing follow-up.
- **Route 53**: one public hosted zone for `aws.tn4consulting.com`.
- **GitHub OIDC**: an `aws_iam_openid_connect_provider` for
  `token.actions.githubusercontent.com` (thumbprint fetched live via a
  `tls_certificate` data source, not hardcoded — GitHub's OIDC TLS chain has
  changed before), plus **one shared IAM role** (not 7 per-repo roles) with a
  trust policy matching `repo:tn4consulting/mfe-pot-*:ref:refs/heads/main` —
  confirmed via `git remote -v` that all 7 repos share this prefix. Scoped to
  `main` only. One shared role is deliberate PoC pragmatism: all 7 repos are
  one trust boundary here, not appropriate for genuine multi-tenancy.
  - Permissions: ECR push/pull scoped to the 11 repo ARNs,
    `eks:DescribeCluster` scoped to a fixed cluster ARN (`mfe-pot` — EKS
    cluster ARNs are name-based, referenceable even before the cluster
    exists).
- **Deliberately not here**: the EKS cluster's own OIDC issuer and any IRSA
  roles. EKS's per-cluster issuer URL contains a random ID that changes every
  destroy/recreate — an IRSA trust policy pinned to today's issuer would
  silently stop matching next cycle. Those live in `cluster/`, recreated each
  time, correctly coupled to one cluster instance.

### `cluster/` (ephemeral — apply before a demo, destroy after)

- **VPC**: 2 AZs (EKS's minimum), public+private subnet per AZ, nodes in
  private subnets, single NAT gateway (the middle ground between paying for
  HA this PoC doesn't need and pushing every node onto a public IP to save a
  few cents per session).
- **EKS cluster**: fixed name `mfe-pot`, `authentication_mode = "API"` (Access
  Entries only, no `aws-auth` ConfigMap), Kubernetes 1.31 pinned explicitly
  (**not** the local kind pin `v1.27.3`, which is only a cgroup-v1 Docker
  workaround on the dev machine, not an intentional target — check AWS's
  current supported versions before applying if this doc is stale by then).
  Public endpoint access, since GitHub-hosted Actions runners have no stable
  IP range to allowlist and this is a PoC, not a hardened environment.
- **Managed node group**: 2× `t3.medium`, on-demand (not spot — an
  interruption mid-demo is worse than the small savings; `capacity_type` is a
  variable so spot stays a one-line opt-in for solo iteration). Sized for
  ~20 pods total (6 frontends + 3 BFFs + mock-idp + strapi + redis +
  ingress-nginx + external-dns + cert-manager + coredns/kube-proxy/vpc-cni).
  Fargate rejected: no DaemonSet support and NLB target-type-`ip` wiring adds
  real complexity for no benefit at this scale.
- **Access Entries**: the foundation-layer CI role gets
  `AmazonEKSClusterAdminPolicy` at cluster scope — this is what lets CI's IAM
  identity actually `helm upgrade` against the cluster. Cluster-admin is
  pragmatic for a single-trusted-team PoC; a namespace-scoped policy is a
  least-privilege follow-up, not built now.
- **IRSA roles** (via `terraform-aws-modules/iam/aws`'s built-in presets):
  `external-dns` and `cert-manager`, each scoped to
  `route53:ChangeResourceRecordSets` on the one delegated zone ARN.

### Cluster addons: Terraform `helm_release`, not a separate bootstrap script

`ingress-nginx`, `external-dns`, and `cert-manager` are all `helm_release`
resources inside `cluster/`'s own state — not an imperative script run after
`apply`. A separate script would be one more manual step before every demo
and, worse, one more thing `terraform destroy` doesn't know how to sequence
on the way down. Folding addons into the same state means one `apply` → fully
working ingress+DNS+TLS, and one `destroy` tears everything down in the
correct order automatically.

**Two ordering details worth knowing, not discovering live:**

1. **Provider bootstrap**: the `kubernetes`/`helm`/`kubectl` providers all
   authenticate via the `exec`-plugin pattern (`aws eks get-token`) against
   the EKS module's own endpoint/CA outputs — this is what lets Terraform's
   graph correctly sequence every `helm_release`/`kubectl_manifest` after the
   cluster genuinely exists. The very first `apply` against a brand-new
   cluster occasionally needs one re-run if the API server isn't reachable
   the instant EKS reports `ACTIVE` — cheap and idempotent, not a design
   flaw.
2. **Destroy ordering / the NLB-and-ENI trap**: `terraform destroy` must tear
   down `helm_release.ingress_nginx` (which deprovisions the real AWS NLB via
   its Service) before the VPC/node group. Because the `helm`/`kubernetes`
   provider blocks reference `module.eks`'s outputs, every `helm_release` in
   `cluster/` implicitly depends on `module.eks` (and transitively
   `module.vpc`, since `eks` depends on `vpc`'s subnet IDs) — Terraform
   destroys dependents before dependencies, so a plain `terraform destroy`
   already tears these down in the right order automatically, no explicit
   `depends_on` needed (and one in the "vpc waits on this" direction isn't
   expressible without a dependency cycle, since vpc must exist *before*
   ingress-nginx can be installed in the first place). The one residual rough
   edge: AWS's own ELB/ENI teardown can lag a minute or two behind the
   Service-delete API call returning, so an immediate VPC/subnet destroy can
   occasionally hit a transient `DependencyViolation`. If that happens, just
   re-run `terraform destroy` — idempotent, succeeds once AWS finishes
   cleanup in the interim.
3. **external-dns record cleanup across cycles**: `policy=sync` + a fixed,
   cluster-instance-independent `txtOwnerId` (`mfe-pot`, not derived from any
   per-cluster ID) so a freshly recreated cluster's external-dns recognizes
   and reconciles the TXT ownership records the previous incarnation left
   behind — makes the up/down cycle self-healing instead of accumulating
   stale Route 53 records.

**TLS**: added via cert-manager + a `ClusterIssuer` per environment
(`letsencrypt-staging`/`letsencrypt-prod`, both always created; which one a
given app uses is chosen per-app via its own `values-eks.yaml`), DNS-01 via
the Route53 solver against the same delegated zone. This is a real domain now,
demoed in a browser against a "government services" UI — HTTP-only reads as
unfinished, and the incremental cost is low since external-dns already
requires the same Route 53 IRSA plumbing. Default to `letsencrypt-staging`
while iterating on this Terraform itself (avoids Let's Encrypt rate limits
across repeated destroy/recreate cycles); switch a given app to `-prod` only
right before an actual demo. Every cluster recreation re-issues fresh
certificates (no cert/key state persists across destroy) — accepted, not
solved, for "a few times a week at most" usage.

## Per-app-repo changes

Worked once against `mfe-pot-job-bank-mfe` (this project's own established
reference-pattern repo — see its `CLAUDE.md`), repeats unchanged in shape
across the other 7 charts.

**New `charts/job-bank-mfe/values-eks.yaml`** (sibling to `values-kind.yaml`):
- `frontend.image.repository`/`backend.image.repository` → full ECR URIs,
  `pullPolicy: IfNotPresent`. Tag left as a placeholder — CI always overrides
  it via `--set ...image.tag=$GITHUB_SHA`, since the whole point is deploying
  one immutable, traceable commit's image.
- `frontend.runtimeConfig.strapiBaseUrl` → `https://cms.aws.tn4consulting.com`.
- `ingress.host` → `job-bank-mfe.aws.tn4consulting.com`, plus new
  `ingress.tls.enabled: true` / `ingress.tls.clusterIssuer: letsencrypt-prod`.
- `backend.env`'s in-cluster Service DNS values (`REDIS_URL`,
  `MOCK_IDP_JWKS_URL`/`_ISSUER`) stay **unchanged** — identical on EKS and
  kind.

**`charts/job-bank-mfe/templates/ingress.yaml`**: small conditional addition
— guard `.Values.ingress.tls.enabled` to add the `cert-manager.io/cluster-issuer`
annotation and a `spec.tls` block. Defaults `false`, so kind/local is
untouched. Applies identically to all 8 hand-written Ingress templates in the
family (Ingress was deliberately excluded from the shared library charts).

**`.github/workflows/ci.yml`** — new job `deploy-eks`,
`needs: [lint-test-build, kind-validation]`,
`if: github.ref == 'refs/heads/main' && github.event_name == 'push'`:
1. Checkout this repo + sibling `mfe-pot-platform` (same as `kind-validation`
   already does, for the library-chart `file://` dependency).
2. `aws-actions/configure-aws-credentials@v4` via OIDC (`role-to-assume`),
   reading `AWS_GITHUB_ACTIONS_ROLE_ARN`/`AWS_REGION`/`EKS_CLUSTER_NAME` from
   **org-level** GitHub Actions variables, not duplicated per-repo secrets.
3. **Cluster-liveness check** (`aws eks describe-cluster`,
   `continue-on-error: true`) — every later step gated on this output, not
   the job itself. Direct consequence of the ephemeral-cluster decision: most
   pushes to `main` happen while no demo cluster exists, so an unconditional
   deploy step would fail loudly and routinely. This keeps `main` green
   regardless, while still deploying automatically the moment a cluster is
   up.
4. ECR login + `docker/build-push-action@v6`, immutable tag `${{ github.sha }}`
   (not `:latest`) — same BuildKit `npm_token` secret mount as Stage 1.
5. `aws eks update-kubeconfig`, `helm dependency update`,
   `helm upgrade --install ... -f values.yaml -f values-eks.yaml --set ...image.tag=$GITHUB_SHA --wait`.
6. Verify: retry-loop curl the real HTTPS hostname (a longer window than
   Stage 1's — a few minutes — to absorb external-dns propagation + first-time
   ACME issuance on a brand-new Ingress; near-instant on redeploys).

Same pattern repeats for `mfe-pot-msca-shell`, `mfe-pot-job-bank-shell`,
`mfe-pot-dashboard-mfe`, `mfe-pot-employment-insurance-mfe`,
`mfe-pot-employment-life-events-mfe` (last two frontend-only, no BFF
image/tag lines), and `mfe-pot-platform`'s own `mock-idp`/`strapi` charts
(net-new CI needed there — today only `publish-shared-packages.yml` exists,
no per-chart deploy workflow). `session-cache` needs **no** changes.

## Build order and verification milestones

1. **Bootstrap** (local state, hand-run once): create the S3 state bucket.
2. **Confirm AWS credentials work**: `aws sts get-caller-identity` succeeds.
3. **Foundation apply**: ECR, Route 53 zone, GitHub OIDC + shared IAM role.
   Manually add the `route53_name_servers` output wherever
   `tn4consulting.com`'s parent zone lives; confirm with
   `dig NS aws.tn4consulting.com`. Set the 3 org-level GitHub Actions
   variables.
4. **Cluster apply**: VPC, EKS + node group, addons, IRSA, access entries,
   ingress-nginx/external-dns/cert-manager, `ClusterIssuer`s. Verify nodes
   `Ready`, all pods `Running`, an NLB hostname assigned.
5. **Land per-repo changes**, `job-bank-mfe` first, then the other 5 app
   repos, then `mfe-pot-platform`'s mock-idp/strapi charts — one PR per repo.
6. **First real Stage 2 run** (job-bank-mfe merge). Verify in order: image in
   ECR → `helm upgrade --install` succeeds → Ingress shows the host → DNS
   resolves to the NLB (proves external-dns) → HTTPS 200 with a valid cert
   (proves cert-manager). This is the most important integration checkpoint
   in the whole plan.
7. **Repeat for the remaining 7 repos/charts.**
8. **Full-family bring-up**: `mfe-pot/tools/deploy-eks.sh` loops over all 8
   chart-owning repos via `gh workflow run` (since `deploy-eks` only fires on
   a `push`, nothing deploys the moment a fresh cluster comes up otherwise),
   same dependency order as `deploy-local.sh`, then curls all 8 hostnames.
9. **Demo teardown**: `terraform destroy` on `cluster/` only, never
   `foundation/`.
10. **Re-apply for the next demo**: re-run steps 4 and 8; DNS/TLS should
    self-heal (fixed `txtOwnerId` design) with no manual Route 53 cleanup.

## Deliberately out of scope for this pass

- Helm library charts as ECR OCI artifacts (existing TODO, independent of
  cloud choice).
- ElastiCache / managed Redis.
- Namespace-scoped least-privilege IAM/RBAC (cluster-admin access entry +
  broad-ish ECR role are accepted PoC pragmatism, flagged explicitly).
- Persisting TLS cert state across cluster teardown/recreate.
- Per-repo IAM roles instead of one shared GitHub OIDC role.
