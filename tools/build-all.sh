#!/usr/bin/env bash
#
# Builds and publishes every repo's images to GHCR (and, for
# mfe-pot-platform's 3 images, ECR too) WITHOUT touching any live cluster --
# the counterpart to tools/deploy-eks.sh, which by default does the
# opposite (deploy the already-published image, never rebuild). See each
# repo's own .github/workflows/ci.yml (app repos) / deploy-eks.yml (platform)
# for the actual skip_build-gated job logic this triggers.
#
# Why this needs to exist as a separate script rather than just letting
# deploy-eks.sh's default workflow_dispatch rebuild things: the whole point
# of deploy-eks.sh's default (skip_build=true) is to redeploy an
# already-published commit to a freshly recreated cluster without paying
# for a rebuild -- see that script's own header comment. This script is for
# the opposite, less common need: force a fresh build+publish of every
# repo's current main HEAD (e.g. to pre-warm GHCR before a demo, or after
# fixing something that doesn't change source but does change how it
# builds) without also touching whatever cluster happens to be up right
# now. Passes skip_build=false to every repo's workflow_dispatch, which:
#   - app repos (ci.yml): runs lint-test-build -> build-images ->
#     kind-validation (a real local kind smoke test), skips deploy-eks
#     entirely.
#   - mfe-pot-platform (deploy-eks.yml): builds+pushes each image to both
#     ECR and GHCR, skips every deploy step (kubeconfig/helm/verify) --
#     still needs AWS credentials, since the ECR push itself needs them,
#     even though nothing gets deployed.
#
# Run from the mfe-pot meta repo directory (the parent of all the sibling
# checkouts -- see mfe-pot.code-workspace). Does NOT require an EKS cluster
# to exist -- unlike deploy-eks.sh, nothing here touches a live cluster.
#
# Needs: `gh` CLI authenticated with a token that can trigger workflow runs
# on every tn4consulting/mfe-pot-* repo (`gh auth status`). mfe-pot-platform
# additionally needs working AWS credentials configured on ITS OWN GitHub
# Actions side (already set up, not something this script or your local
# AWS CLI needs to provide) -- this script itself makes no AWS calls.
#
# Usage: tools/build-all.sh [-h|--help]

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: tools/build-all.sh [-h|--help]

Triggers every repo's build step (skip_build=false) to force a fresh
build+publish to GHCR (and ECR, for mfe-pot-platform's 3 images) without
deploying anything. Counterpart to tools/deploy-eks.sh's default
(deploy-only, no rebuild) behaviour.

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

GITHUB_ORG="tn4consulting"

fail=0

echo "=== Step 1: preflight ==="
if ! gh auth status > /dev/null 2>&1; then
  echo "error: gh CLI isn't authenticated -- run 'gh auth login' first." >&2
  exit 1
fi
for repo in mfe-pot-platform mfe-pot-job-bank-mfe mfe-pot-employment-insurance-mfe mfe-pot-dashboard-mfe mfe-pot-life-events-mfe mfe-pot-msca-shell mfe-pot-job-bank-shell; do
  if [ ! -d "$repo" ]; then
    echo "error: $repo not found -- run this script from the mfe-pot meta repo directory (see mfe-pot.code-workspace)." >&2
    exit 1
  fi
done
echo "gh credentials OK, all 7 sibling repos present."

# Triggers <repo>'s named workflow via workflow_dispatch with
# skip_build=false, then waits for the specific run it just queued to
# finish. `gh workflow run` doesn't return a run ID directly, so this polls
# gh run list for the newest run of that workflow on main right after
# queuing it -- same small-race caveat as tools/deploy-eks.sh's identical
# helper, acceptable for the same reason (nothing else pushes to these
# repos' main branches during a build session).
run_build() {
  local repo="$1" workflow="$2"
  echo
  echo "--- $repo ($workflow), skip_build=false ---"

  gh workflow run "$workflow" --repo "$GITHUB_ORG/$repo" --ref main -f skip_build=false
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
echo "=== Step 2: build+publish each repo's images ==="
# No dependency ordering needed here (unlike deploy-eks.sh) -- these are
# independent builds with no runtime relationship to each other, so the
# order is just the family's usual platform-first-then-apps convention for
# readability/consistency with deploy-eks.sh, not a real requirement.
run_build "mfe-pot-platform" "deploy-eks.yml"
run_build "mfe-pot-job-bank-mfe" "ci.yml"
run_build "mfe-pot-employment-insurance-mfe" "ci.yml"
run_build "mfe-pot-dashboard-mfe" "ci.yml"
run_build "mfe-pot-life-events-mfe" "ci.yml"
run_build "mfe-pot-msca-shell" "ci.yml"
run_build "mfe-pot-job-bank-shell" "ci.yml"

echo
if [ "$fail" -ne 0 ]; then
  echo "One or more builds failed above -- see !! lines. Fix and re-run (safe -- every step is workflow_dispatch/idempotent image push)." >&2
  exit 1
fi

echo "=== All 7 repos built and published. ==="
cat <<'EOF'

Run tools/deploy-eks.sh next to deploy these freshly-published images to
the real EKS cluster (its default skip_build=true will just deploy what
was published here, no rebuild).
EOF
