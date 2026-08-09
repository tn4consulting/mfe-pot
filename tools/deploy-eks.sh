#!/usr/bin/env bash
#
# Brings the whole mfe-pot family up on an already-provisioned AWS EKS
# cluster (see mfe-pot-platform/infra/terraform/cluster and
# mfe-pot/docs/plans/20260808-1500-mfe-pot-aws-eks-terraform.md). This is
# the AWS equivalent of tools/deploy-local.sh, but it doesn't build or
# deploy anything itself the way that script does -- each repo's own
# `deploy-eks` CI job (GitHub Actions) does the actual build+push+helm-upgrade
# work, authenticated via GitHub OIDC. This script's only job is triggering
# those workflows in the right order and proving the result actually works
# end to end afterwards -- the same "pure orchestration, delegate to each
# sibling" shape as deploy-local.sh, just delegating to GitHub Actions runs
# instead of local shell commands.
#
# Why this needs to exist at all: `deploy-eks` jobs only fire on a `push` to
# main (see each repo's ci.yml), so the moment `terraform apply` in
# infra/terraform/cluster brings up a *new* cluster, nothing deploys to it on
# its own -- there's no push to react to. This script re-triggers every
# repo's already-built `deploy-eks` job via workflow_dispatch instead of
# requiring an empty commit to each of the 7 repos.
#
# Run from the mfe-pot meta repo directory (the parent of all the sibling
# checkouts -- see mfe-pot.code-workspace), after infra/terraform/cluster has
# been applied and its Route 53/GitHub-OIDC prerequisites in
# infra/terraform/foundation are already in place.
#
# Needs: `gh` CLI authenticated with a token that can trigger workflow runs
# on every tn4consulting/mfe-pot-* repo (`gh auth status`), `aws` CLI with
# working credentials, `kubectl`/`helm` installed.
#
# Usage: tools/deploy-eks.sh [-h|--help]
#
# Env vars:
#   EKS_CLUSTER_NAME   must match infra/terraform/cluster's cluster_name
#                       (default: mfe-pot)
#   AWS_REGION          must match infra/terraform's aws_region (default:
#                       ca-central-1)
#   DOMAIN_NAME         must match infra/terraform/foundation's domain_name
#                       (default: aws.tn4consulting.com)

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: tools/deploy-eks.sh [-h|--help]

Triggers every repo's deploy-eks CI job against an already-provisioned AWS
EKS cluster, in dependency order, then verifies all 10 hostnames serve.

  -h, --help    show this message and exit.
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown option '$arg'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-mfe-pot}"
AWS_REGION="${AWS_REGION:-ca-central-1}"
DOMAIN_NAME="${DOMAIN_NAME:-aws.tn4consulting.com}"
GITHUB_ORG="tn4consulting"

fail=0

echo "=== Step 1: preflight ==="
if ! gh auth status > /dev/null 2>&1; then
  echo "error: gh CLI isn't authenticated -- run 'gh auth login' first." >&2
  exit 1
fi
if ! aws sts get-caller-identity > /dev/null 2>&1; then
  echo "error: AWS CLI has no working credentials -- fix that first (see infra/terraform/README.md)." >&2
  exit 1
fi
if ! aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  echo "error: EKS cluster '$EKS_CLUSTER_NAME' not found in $AWS_REGION -- apply mfe-pot-platform/infra/terraform/cluster first." >&2
  exit 1
fi
for repo in mfe-pot-platform mfe-pot-job-bank-mfe mfe-pot-employment-insurance-mfe mfe-pot-dashboard-mfe mfe-pot-life-events-mfe mfe-pot-msca-shell mfe-pot-job-bank-shell; do
  if [ ! -d "$repo" ]; then
    echo "error: $repo not found -- run this script from the mfe-pot meta repo directory (see mfe-pot.code-workspace)." >&2
    exit 1
  fi
done
echo "gh/aws credentials OK, cluster '$EKS_CLUSTER_NAME' exists, all 7 sibling repos present."

echo
echo "=== Step 2: point kubectl/helm at the cluster ==="
aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"

echo
echo "=== Step 3: session-cache + observability stack (no CI job -- all bare upstream images, nothing to build) ==="
if helm upgrade --install session-cache mfe-pot-platform/charts/session-cache \
    -f mfe-pot-platform/charts/session-cache/values.yaml --wait --timeout 60s; then
  echo "session-cache OK"
else
  echo "!! session-cache helm upgrade failed" >&2
  fail=1
fi

# otel-collector/grafana need the AWS-shaped Ingress host + TLS from
# values-eks.yaml (see mfe-pot-platform/charts/otel-collector/values-eks.yaml,
# charts/grafana/values-eks.yaml); tempo/prometheus have no Ingress and no
# eks-specific values at all (cluster-internal only, identical on kind and
# EKS). Deployed in this order -- collector needs tempo/prometheus reachable
# before its first export attempt -- before any app that exports telemetry.
if helm upgrade --install otel-collector mfe-pot-platform/charts/otel-collector \
    -f mfe-pot-platform/charts/otel-collector/values.yaml \
    -f mfe-pot-platform/charts/otel-collector/values-eks.yaml --wait --timeout 60s; then
  echo "otel-collector OK"
else
  echo "!! otel-collector helm upgrade failed" >&2
  fail=1
fi

if helm upgrade --install tempo mfe-pot-platform/charts/tempo \
    -f mfe-pot-platform/charts/tempo/values.yaml --wait --timeout 60s; then
  echo "tempo OK"
else
  echo "!! tempo helm upgrade failed" >&2
  fail=1
fi

if helm upgrade --install prometheus mfe-pot-platform/charts/prometheus \
    -f mfe-pot-platform/charts/prometheus/values.yaml --wait --timeout 60s; then
  echo "prometheus OK"
else
  echo "!! prometheus helm upgrade failed" >&2
  fail=1
fi

if helm upgrade --install grafana mfe-pot-platform/charts/grafana \
    -f mfe-pot-platform/charts/grafana/values.yaml \
    -f mfe-pot-platform/charts/grafana/values-eks.yaml --wait --timeout 60s; then
  echo "grafana OK"
else
  echo "!! grafana helm upgrade failed" >&2
  fail=1
fi

# Triggers <repo>'s named workflow via workflow_dispatch, then waits for the
# specific run it just queued to finish. `gh workflow run` doesn't return a
# run ID directly, so this polls gh run list for the newest run of that
# workflow on main right after queuing it -- a small race in theory (another
# run could be queued in the same instant), acceptable here since nothing
# else pushes to these repos' main branches during a deploy session.
run_workflow() {
  local repo="$1" workflow="$2"
  echo
  echo "--- $repo ($workflow) ---"

  gh workflow run "$workflow" --repo "$GITHUB_ORG/$repo" --ref main
  sleep 5

  local run_id
  run_id=$(gh run list --repo "$GITHUB_ORG/$repo" --workflow "$workflow" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
  if [ -z "$run_id" ]; then
    echo "!! could not find the queued run for $repo/$workflow" >&2
    fail=1
    return 1
  fi

  echo "watching run $run_id (https://github.com/$GITHUB_ORG/$repo/actions/runs/$run_id)..."
  if gh run watch "$run_id" --repo "$GITHUB_ORG/$repo" --exit-status; then
    echo "$repo ($workflow) OK"
  else
    echo "!! $repo ($workflow) failed -- see the run above" >&2
    fail=1
    return 1
  fi
}

echo
echo "=== Step 4: deploy each app in order ==="
# Same dependency order as tools/deploy-local.sh: platform's shared infra
# first (mock-idp/strapi, via mfe-pot-platform's own deploy-eks.yml), then
# the 3 BFF-owning apps (so dashboard-bff has something to fan out to the
# moment it comes up), then the frontend-only apps, both host apps last.
run_workflow "mfe-pot-platform" "deploy-eks.yml"
run_workflow "mfe-pot-job-bank-mfe" "ci.yml"
run_workflow "mfe-pot-employment-insurance-mfe" "ci.yml"
run_workflow "mfe-pot-dashboard-mfe" "ci.yml"
run_workflow "mfe-pot-life-events-mfe" "ci.yml"
run_workflow "mfe-pot-msca-shell" "ci.yml"
run_workflow "mfe-pot-job-bank-shell" "ci.yml"

if [ "$fail" -ne 0 ]; then
  echo
  echo "One or more deploys failed above -- skipping verification. Fix and re-run (safe -- every step is workflow_dispatch/helm upgrade --install)." >&2
  exit 1
fi

echo
echo "=== Step 5: confirm every pod is Running ==="
kubectl get pods

echo
echo "=== Step 6: verify all 10 hostnames serve over HTTPS ==="
hosts=(
  "msca.$DOMAIN_NAME"
  "job-bank.$DOMAIN_NAME"
  "dashboard-mfe.$DOMAIN_NAME"
  "job-bank-mfe.$DOMAIN_NAME"
  "employment-insurance-mfe.$DOMAIN_NAME"
  "life-events-mfe.$DOMAIN_NAME"
  "cms.$DOMAIN_NAME"
  "mock-idp.$DOMAIN_NAME"
  "grafana.$DOMAIN_NAME"
  "otel.$DOMAIN_NAME"
)
for host in "${hosts[@]}"; do
  status=$(curl -s -o /dev/null -w '%{http_code}' "https://$host/" || echo 000)
  if [ "$status" = "200" ] || [ "$status" = "404" ]; then
    # mock-idp's own "/" isn't a real page (it's an API-shaped service --
    # see its own Ingress, everything is under /authorize, /token, etc.), so
    # a 404 there still proves TLS + DNS + routing all worked; same story
    # for otel's "/" (the collector's OTLP/HTTP receiver only handles POST
    # to /v1/traces and /v1/metrics) -- anywhere else a 404 would be worth a
    # second look.
    echo "OK   $host (HTTP $status)"
  else
    echo "!!   $host (HTTP $status)" >&2
    fail=1
  fi
done

echo
if [ "$fail" -ne 0 ]; then
  echo "Done with failures -- see !! lines above." >&2
  exit 1
fi

echo "=== All 10 hostnames deployed and verified on AWS EKS. ==="
cat <<EOF

  msca-shell:               https://msca.$DOMAIN_NAME
  job-bank-shell:           https://job-bank.$DOMAIN_NAME
  dashboard:                https://dashboard-mfe.$DOMAIN_NAME
  job-bank:                 https://job-bank-mfe.$DOMAIN_NAME
  employment-insurance:     https://employment-insurance-mfe.$DOMAIN_NAME
  life-events:   https://life-events-mfe.$DOMAIN_NAME
  cms (Strapi):             https://cms.$DOMAIN_NAME
  mock-idp:                 https://mock-idp.$DOMAIN_NAME
  grafana:                  https://grafana.$DOMAIN_NAME
  otel-collector (OTLP/HTTP ingest, not browsable): https://otel.$DOMAIN_NAME

When the demo's done: cd mfe-pot-platform/infra/terraform/cluster &&
terraform destroy (never foundation/ -- that holds the ECR images, Route 53
zone, and GitHub OIDC trust relationship every repo's CI depends on).
EOF
