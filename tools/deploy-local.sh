#!/usr/bin/env bash
#
# Stands up the whole mfe-pot family on a single local kind cluster:
# mfe-pot-platform's shared infra (Strapi + the session-cache Redis
# instance), then the 3 BFF-owning apps (job-bank, employment-insurance,
# dashboard), then the 2 frontend-only apps (employment-life-events,
# shell). Each step just delegates to that sibling repo's own
# tools/deploy-local.sh -- this script's only job is running them in a
# sensible order against one shared cluster and proving the result
# actually works end to end afterwards.
#
# Run from the mfe-pot meta repo directory (the parent of all the
# sibling checkouts -- see mfe-pot.code-workspace for the expected
# layout).
#
# Needs: Docker running, and a GitHub credential with read:packages
# access to @tn4consulting/* (gh auth login, or NODE_AUTH_TOKEN/
# GITHUB_TOKEN set) that stays valid for the duration of a Docker build
# (~60-90s) -- a short-lived token can expire mid-build; re-run this
# script if a step fails with ERR_PNPM_FETCH_401/403.
#
# Safe to re-run any time -- every step is `helm upgrade --install`, and
# the persistence check at the end only ever adds one throwaway
# "rollout-check" record per BFF, never touching any other data.

set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mfe-pot}"
CONTEXT="kind-$CLUSTER_NAME"

# name -> repo dir. Order matters: platform's shared infra first, then
# the 3 BFF-owning apps (so dashboard-bff has something to fan out to
# the moment it comes up), then the 2 frontend-only apps. Two parallel
# arrays, not an associative array -- macOS's default /bin/bash (3.2)
# predates `declare -A` support.
STEPS=(
  "mfe-pot-platform"
  "mfe-pot-job-bank"
  "mfe-pot-employment-insurance"
  "mfe-pot-dashboard"
  "mfe-pot-employment-life-events"
  "mfe-pot-shell"
)
# Backend deployment name per entry above, "" for frontend-only apps --
# used to force a post-deploy rollout restart (see the comment below).
STEP_BACKENDS=(
  ""
  "job-bank-bff"
  "employment-insurance-bff"
  "dashboard-bff"
  ""
  ""
)

fail=0

echo "=== Step 1: preflight ==="
if ! docker info > /dev/null 2>&1; then
  echo "error: Docker isn't running." >&2
  exit 1
fi
for repo in "${STEPS[@]}"; do
  if [ ! -d "$repo" ]; then
    echo "error: $repo not found -- run this script from the mfe-pot meta repo directory (see mfe-pot.code-workspace)." >&2
    exit 1
  fi
done
echo "Docker is running, all 6 sibling repos present."

echo
echo "=== Step 2: deploy each app in order ==="
for i in "${!STEPS[@]}"; do
  repo="${STEPS[$i]}"
  echo
  echo "--- $repo ---"
  (
    set -e
    cd "$repo"
    git pull --ff-only
    CLUSTER_NAME="$CLUSTER_NAME" bash tools/deploy-local.sh
  )
  if [ $? -ne 0 ]; then
    echo "!! $repo deploy failed" >&2
    fail=1
    continue
  fi

  backend="${STEP_BACKENDS[$i]}"
  if [ -n "$backend" ]; then
    # `kind load docker-image` overwrites the "kind" tag's content in
    # containerd, but a pod already running under that tag never
    # notices -- Kubernetes only recreates pods when the pod *spec*
    # changes (image reference string, directly-inlined env), not when
    # a mutable tag's underlying bytes change or when a ConfigMap
    # referenced via `envFrom` is updated in place. Without this,
    # `helm upgrade` can silently leave the *old* binary running
    # indefinitely across any number of rebuilds.
    echo "forcing a rollout so $backend actually picks up the freshly-built image..."
    kubectl --context "$CONTEXT" rollout restart "deployment/$backend"
    kubectl --context "$CONTEXT" rollout status "deployment/$backend" --timeout=60s
  fi
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "One or more deploys failed above -- skipping verification. Fix and re-run." >&2
  exit 1
fi

echo
echo "=== Step 3: confirm every pod is Running ==="
kubectl --context "$CONTEXT" get pods

echo
echo "=== Step 4: prove each BFF persists through a pod restart (real Redis, not in-memory) ==="

check_persistence() {
  local label=$1 host=$2 create_path=$3 create_body=$4 read_path=$5 jq_filter=$6

  echo
  echo "--- $label ---"
  curl -sf -X POST -H "Host: $host" -H "Content-Type: application/json" \
    -d "$create_body" "http://localhost$create_path" > /dev/null \
    && echo "created test data" || { echo "!! failed to create test data"; fail=1; return 1; }

  before=$(curl -s -H "Host: $host" "http://localhost$read_path" | jq -r "$jq_filter")
  echo "before restart: $before"

  kubectl --context "$CONTEXT" delete pod -l "app.kubernetes.io/name=$label" --wait=true > /dev/null
  kubectl --context "$CONTEXT" wait --for=condition=ready pod -l "app.kubernetes.io/name=$label" --timeout=60s > /dev/null

  after=$(curl -s -H "Host: $host" "http://localhost$read_path" | jq -r "$jq_filter")
  echo "after restart:  $after"

  if [ "$before" = "$after" ] && [ -n "$before" ] && [ "$before" != "0" ] && [ "$before" != "null" ]; then
    echo "OK: data survived the pod restart -- reading from real Redis."
  else
    echo "!! MISMATCH: data did not survive the restart -- check REDIS_URL / session-cache reachability."
    fail=1
  fi

  # Deliberately NOT calling /api/reset here -- it clears every sub's
  # data for this BFF, not just the "rollout-check" test data this
  # function creates, which would also wipe any real demo state (e.g.
  # mock-citizen-001's claim) built up separately. The leftover
  # "rollout-check" record is harmless; clean it up yourself with a
  # manual POST /api/reset if you actually want a clean slate.
}

check_persistence \
  "job-bank-bff" "job-bank.mfe-pot.local" \
  "/api/applications" '{"jobId":"job-001","applicantSub":"rollout-check"}' \
  "/api/applications?applicantSub=rollout-check" "length"

check_persistence \
  "employment-insurance-bff" "employment-insurance.mfe-pot.local" \
  "/api/applications" '{"applicantSub":"rollout-check"}' \
  "/api/claims?applicantSub=rollout-check" ".id"

echo
echo "--- dashboard-bff (seeded persona, no create step needed) ---"
before=$(curl -s -H "Host: dashboard.mfe-pot.local" "http://localhost/api/payments?sub=mock-citizen-001" | jq "length")
echo "payments before restart: $before"
kubectl --context "$CONTEXT" delete pod -l "app.kubernetes.io/name=dashboard-bff" --wait=true > /dev/null
kubectl --context "$CONTEXT" wait --for=condition=ready pod -l "app.kubernetes.io/name=dashboard-bff" --timeout=60s > /dev/null
after=$(curl -s -H "Host: dashboard.mfe-pot.local" "http://localhost/api/payments?sub=mock-citizen-001" | jq "length")
echo "payments after restart:  $after"
if [ "$before" = "$after" ] && [ -n "$before" ] && [ "$before" != "0" ] && [ "$before" != "null" ]; then
  echo "OK: seeded payments survived the pod restart -- reading from real Redis."
else
  echo "!! MISMATCH: payments did not survive the restart."
  fail=1
fi
# No /api/reset call here either -- this check only reads, never
# creates data, so there's nothing of its own to clean up.

echo
if [ "$fail" -ne 0 ]; then
  echo "Done with failures -- see !! lines above." >&2
  exit 1
fi

echo "=== All 6 apps deployed and verified. ==="
cat <<EOF

  shell:                    http://shell.mfe-pot.local
  dashboard:                http://dashboard.mfe-pot.local
  job-bank:                 http://job-bank.mfe-pot.local
  employment-insurance:     http://employment-insurance.mfe-pot.local
  employment-life-events:   http://employment-life-events.mfe-pot.local
  cms (Strapi):             http://cms.mfe-pot.local

(all via the ingress-nginx controller on localhost -- add the above
hostnames to /etc/hosts pointing at 127.0.0.1, or pass -H "Host: ..."
with curl, same as this script does.)
EOF
