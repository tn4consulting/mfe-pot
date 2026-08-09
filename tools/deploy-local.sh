#!/usr/bin/env bash
#
# Stands up the whole mfe-pot family on a single local kind cluster:
# mfe-pot-platform's shared infra (Strapi, the session-cache Redis
# instance, the Unleash feature-flag server, and mock-idp), then the 3
# BFF-owning apps (job-bank,
# employment-insurance, dashboard), then the 3 frontend-only apps
# (life-events, msca-shell, job-bank-shell -- two independent
# host apps sharing one mock-idp/Strapi, proving the federation pattern
# generalizes to more than one shell). Each step just delegates to that
# sibling repo's own tools/deploy-local.sh -- this script's only job is
# running them in a sensible order against one shared cluster and
# proving the result actually works end to end afterwards.
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
#
# Skip-if-unchanged: each sibling repo is only rebuilt/redeployed when
# its own git tree (HEAD + any uncommitted/untracked changes) differs
# from the tree last successfully deployed, AND its helm release(s) are
# still actually present on the cluster. State lives in .deploy-state/
# (gitignored), one file per repo. Known blind spot: this only looks at
# each repo's own git tree, not at published @tn4consulting/* package
# versions it pulls in via pnpm during the image build -- if you bump/
# publish a shared lib in mfe-pot-platform and want a downstream app to
# pick it up without any change to the app repo itself, use -f.
#
# Usage: tools/deploy-local.sh [-f|--force] [-h|--help]
#   -f, --force   rebuild and redeploy every app regardless of whether
#                 its git tree changed since the last successful deploy.
#   -h, --help    show this message and exit.
#
# Env vars:
#   CLUSTER_NAME        kind cluster name (default: kind -- matches every
#                       sibling repo's own tools/deploy-local.sh default
#                       and this README's manual walkthrough, so that
#                       running a single sibling's deploy-local.sh
#                       afterward reuses the same cluster this script
#                       created, without needing an explicit override)
#   DOCKER_MIN_FREE_GB  free-disk threshold that triggers a Docker
#                       build-cache/dangling-image prune before building
#                       (default: 15)

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: tools/deploy-local.sh [-f|--force] [-h|--help]

  -f, --force   rebuild and redeploy every app regardless of whether its
                git tree changed since the last successful deploy.
  -h, --help    show this message and exit.
EOF
}

FORCE=0
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown option '$arg'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

CLUSTER_NAME="${CLUSTER_NAME:-kind}"
CONTEXT="kind-$CLUSTER_NAME"
DOCKER_MIN_FREE_GB="${DOCKER_MIN_FREE_GB:-15}"
STATE_DIR="$(dirname "${BASH_SOURCE[0]}")/../.deploy-state"

# name -> repo dir. Order matters: platform's shared infra first, then
# the 3 BFF-owning apps (so dashboard-bff has something to fan out to
# the moment it comes up), then the 3 frontend-only apps -- both host
# apps last, since job-bank-shell only needs job-bank-mfe up and msca-shell
# needs all 4 remotes up. Parallel arrays, not associative arrays --
# macOS's default /bin/bash (3.2) predates `declare -A` support.
STEPS=(
  "mfe-pot-platform"
  "mfe-pot-job-bank-mfe"
  "mfe-pot-employment-insurance-mfe"
  "mfe-pot-dashboard-mfe"
  "mfe-pot-life-events-mfe"
  "mfe-pot-msca-shell"
  "mfe-pot-job-bank-shell"
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
  ""
)
# Space-separated helm release name(s) per entry above -- used to check
# whether a repo's release(s) are still actually present on the cluster
# before trusting a "nothing changed" skip (e.g. after the cluster was
# torn down and recreated without this script's state being reset).
STEP_RELEASES=(
  "session-cache unleash strapi mock-idp"
  "job-bank-mfe"
  "employment-insurance-mfe"
  "dashboard-mfe"
  "life-events-mfe"
  "msca-shell"
  "job-bank-shell"
)

fail=0

hash_stdin() {
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

# Signature of a repo's current working tree: HEAD commit + any
# uncommitted changes to tracked files + the content of any untracked
# (but not gitignored) files. Good enough to answer "would a fresh
# `docker build .` in this repo produce different output than last
# time" without actually running the build.
repo_signature() {
  local repo="$1"
  {
    git -C "$repo" rev-parse HEAD
    git -C "$repo" diff HEAD --
    git -C "$repo" ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
      printf '%s\n' "$f"
      cat "$repo/$f" 2> /dev/null
    done
  } | hash_stdin
}

# Is every helm release for this step actually present and deployed?
releases_present() {
  local releases="$1"
  local rel
  for rel in $releases; do
    helm status "$rel" --kube-context "$CONTEXT" > /dev/null 2>&1 || return 1
  done
  return 0
}

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
mkdir -p "$STATE_DIR"
echo "Docker is running, all 7 sibling repos present."

echo
echo "=== Step 2: check disk space for Docker/kind builds ==="
# NOTE: `df /` on the *host* only reflects real Docker disk pressure on
# Linux, where dockerd talks to the host filesystem directly. On Docker
# Desktop (macOS/Windows) all builds/images/the kind node itself live
# inside a VM with its own separate virtual disk, completely disconnected
# from host free space -- host `df` can read 100+GB free while the VM
# backing Docker is 100% full. So: show `docker system df` for visibility,
# but the disk that actually matters for `kind`-hosted workloads is the
# kind node container's own root filesystem, checked directly via
# `docker exec` when the node exists. Each app image is rebuilt under the
# *same* mutable ":kind" tag every run, and `kind load docker-image`
# leaves the previous, now-untagged image ID behind in the node's
# containerd store instead of replacing it -- these accumulate silently
# across runs (confirmed: 125 images / ~66GB on one cluster that had
# never been pruned) until the node's disk fills and writes inside pods
# start failing with "No space left on device" (surfaced first as Redis
# refusing writes, then as 500s from whichever BFF touched it).
docker system df

NODE_CONTAINER="${CLUSTER_NAME}-control-plane"
low_disk=0
if docker exec "$NODE_CONTAINER" true > /dev/null 2>&1; then
  read -r avail_kb used_pct < <(docker exec "$NODE_CONTAINER" df -Pk / | awk 'NR==2 {gsub("%","",$5); print $4, $5}')
  avail_gb=$((avail_kb / 1024 / 1024))
  echo "kind node ($NODE_CONTAINER) root filesystem: ${avail_gb}GB free (${used_pct}% used)"
  [ "$avail_gb" -lt "$DOCKER_MIN_FREE_GB" ] && low_disk=1
else
  echo "kind node not up yet (first run creates it in Step 3) -- nothing to check there yet."
fi

if [ "$low_disk" -eq 1 ]; then
  echo "low disk on the kind node (threshold ${DOCKER_MIN_FREE_GB}GB) -- pruning Docker build cache/dangling images plus unreferenced images inside the node..."
  docker builder prune -f
  docker image prune -f
  docker exec "$NODE_CONTAINER" crictl rmi --prune > /dev/null 2>&1 || true
  avail_kb=$(docker exec "$NODE_CONTAINER" df -Pk / | awk 'NR==2 {print $4}')
  avail_gb=$((avail_kb / 1024 / 1024))
  echo "after prune: ${avail_gb}GB free on the kind node."
  if [ "$avail_gb" -lt "$DOCKER_MIN_FREE_GB" ]; then
    echo "warning: still under ${DOCKER_MIN_FREE_GB}GB free on the kind node after pruning build cache/dangling/unreferenced images -- an in-use image can't be pruned out from under a running pod. Recreate the node for a full reclaim: 'kind delete cluster --name $CLUSTER_NAME' then re-run this script (safe -- see the header comment), or 'docker system prune -a --volumes' by hand for a deeper host-level clean (not run automatically here since it can remove tagged images/volumes from other projects)." >&2
  fi
fi

echo
echo "=== Step 3: deploy each app in order ==="
for i in "${!STEPS[@]}"; do
  repo="${STEPS[$i]}"
  backend="${STEP_BACKENDS[$i]}"
  releases="${STEP_RELEASES[$i]}"
  echo
  echo "--- $repo ---"

  # `git pull`'s own "Already up to date." here means only "this repo's
  # local branch matches its remote" -- it says nothing about whether a
  # rebuild is needed. That's a genuinely separate question, answered by
  # the deploy-state signature check right below, and the two "up to
  # date"-sounding messages back to back read as contradictory when the
  # rebuild check decides to proceed anyway (e.g. because of local
  # commits never pushed to the remote, which `git pull` can't see at
  # all). Labelled explicitly so the two checks don't look like one.
  echo "checking $repo's remote for updates:"
  if ! (cd "$repo" && git pull --ff-only); then
    echo "!! $repo git pull failed" >&2
    fail=1
    continue
  fi

  sig="$(repo_signature "$repo")"
  prev_sig=""
  [ -f "$STATE_DIR/$repo.sha" ] && prev_sig="$(cat "$STATE_DIR/$repo.sha")"

  if [ "$FORCE" -eq 0 ] && [ -n "$prev_sig" ] && [ "$sig" = "$prev_sig" ] && releases_present "$releases"; then
    echo "deploy-state check: up to date -- no changes since last deploy and release(s) [$releases] already running. Skipping build+deploy (use -f to force)."
    continue
  fi

  if [ "$FORCE" -eq 1 ]; then
    echo "deploy-state check: -f/--force passed, rebuilding regardless."
  elif [ -z "$prev_sig" ]; then
    echo "deploy-state check: no prior successful deploy recorded for $repo -- building."
  elif [ "$sig" != "$prev_sig" ]; then
    echo "deploy-state check: working tree changed since the last deploy (commits, staged/unstaged edits, or untracked files) -- building."
  else
    echo "deploy-state check: working tree unchanged, but release(s) [$releases] aren't all present on the cluster -- building."
  fi

  (
    set -e
    cd "$repo"
    CLUSTER_NAME="$CLUSTER_NAME" bash tools/deploy-local.sh
  )
  if [ $? -ne 0 ]; then
    echo "!! $repo deploy failed" >&2
    fail=1
    continue
  fi
  echo "$sig" > "$STATE_DIR/$repo.sha"

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
echo "=== Step 4: confirm every pod is Running ==="
kubectl --context "$CONTEXT" get pods

echo
echo "=== Step 5: prove each BFF persists through a pod restart (real Redis, not in-memory) ==="

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
  "job-bank-bff" "job-bank-mfe.mfe-pot.local" \
  "/api/applications" '{"jobId":"job-001","applicantSub":"rollout-check"}' \
  "/api/applications?applicantSub=rollout-check" "length"

# employment-insurance-bff's POST /api/applications now requires a full
# EiApplicationInput (with declarationAccepted=true) alongside
# applicantSub, not just applicantSub alone -- see the EI application
# wizard (EiApplicationForm.tsx in mfe-pot-employment-insurance-mfe). A
# bare `{"applicantSub":"rollout-check"}` 400s here since the route added
# that requirement; kept as its own variable rather than inlined, purely
# for readability given the payload's size.
ei_application_body='{"applicantSub":"rollout-check","application":{"personal":{"firstName":"Rollout","lastName":"Check","dateOfBirth":"1990-01-01","addressLine1":"123 Main St","city":"Ottawa","province":"ON","postalCode":"K1A 0A1","phone":"6135550100","preferredLanguage":"en"},"separation":{"employerName":"Acme Co.","lastDayWorked":"2026-07-01","reasonCode":"shortage_of_work","payRate":25,"payPeriod":"hourly","jobTitle":"Warehouse associate"},"otherEmployment":{"hadOtherEmployers":false},"eligibility":{"workersCompensation":false,"pension":false,"selfEmployedOrBusiness":false,"inTrainingProgram":false},"availability":{"availableImmediately":true,"educationLevel":"high_school"},"directDeposit":{"enrolling":false},"declarationAccepted":true}}'

check_persistence \
  "employment-insurance-bff" "employment-insurance-mfe.mfe-pot.local" \
  "/api/applications" "$ei_application_body" \
  "/api/claims?applicantSub=rollout-check" ".id"

echo
echo "--- dashboard-bff (seeded persona, no create step needed) ---"
before=$(curl -s -H "Host: dashboard-mfe.mfe-pot.local" "http://localhost/api/payments?sub=mock-citizen-001" | jq "length")
echo "payments before restart: $before"
kubectl --context "$CONTEXT" delete pod -l "app.kubernetes.io/name=dashboard-bff" --wait=true > /dev/null
kubectl --context "$CONTEXT" wait --for=condition=ready pod -l "app.kubernetes.io/name=dashboard-bff" --timeout=60s > /dev/null
after=$(curl -s -H "Host: dashboard-mfe.mfe-pot.local" "http://localhost/api/payments?sub=mock-citizen-001" | jq "length")
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

echo "=== All 7 apps deployed and verified. ==="
cat <<EOF

  msca-shell:               http://msca.mfe-pot.local
  job-bank-shell:           http://job-bank.mfe-pot.local
  dashboard:                http://dashboard-mfe.mfe-pot.local
  job-bank:                 http://job-bank-mfe.mfe-pot.local
  employment-insurance:     http://employment-insurance-mfe.mfe-pot.local
  life-events:   http://life-events-mfe.mfe-pot.local
  cms (Strapi):             http://cms.mfe-pot.local

(all via the ingress-nginx controller on localhost -- add the above
hostnames to /etc/hosts pointing at 127.0.0.1, or pass -H "Host: ..."
with curl, same as this script does.)
EOF
