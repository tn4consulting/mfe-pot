#!/usr/bin/env bash
#
# Shows/switches which cluster kubectl is currently pointed at -- the local
# kind cluster (from tools/deploy-local.sh) or the AWS EKS cluster (from
# tools/deploy-eks.sh + mfe-pot-platform/infra/terraform/cluster). Both
# clusters commonly coexist in the same kubeconfig, and running the wrong
# one's kubectl/helm commands against the other is an easy mistake -- this
# just makes the active context (and the switch) explicit instead of having
# to remember `kubectl config current-context`'s raw output.
#
# By default, `local`/`eks` switch only the *current shell*, not
# ~/.kube/config's global current-context (which every shell on the machine
# shares) -- so one terminal can stay pinned to kind while another points at
# EKS. This works by pointing KUBECONFIG at a tiny per-shell override file
# (just a `current-context:` line) layered in front of the real kubeconfig;
# kubectl's merge rules take current-context from the first file in the
# KUBECONFIG list that sets it, while clusters/users/contexts still come
# from the real file, so nothing about the actual cluster definitions is
# duplicated or can go stale. Because that only changes an env var, it can't
# take effect in a subshell the normal way -- these subcommands print an
# `export KUBECONFIG=...` line that you eval in your current shell.
#
# Usage:
#   tools/kctx.sh                    show current context, flagged local/eks/other
#   tools/kctx.sh list                list all contexts, each flagged the same way
#   eval "$(tools/kctx.sh local)"     point THIS shell at the kind context
#   eval "$(tools/kctx.sh eks)"       point THIS shell at the EKS context
#   tools/kctx.sh local --global      switch ~/.kube/config's context for every shell
#   tools/kctx.sh eks --global        (old behaviour -- kubectl config use-context)
#   tools/kctx.sh -h | --help         show this message and exit
#
# Env vars:
#   CLUSTER_NAME        kind cluster name (default: mfe-pot) -- must match
#                       tools/deploy-local.sh
#   EKS_CLUSTER_NAME     EKS cluster name (default: mfe-pot) -- must match
#                       tools/deploy-eks.sh / infra/terraform/cluster
#   AWS_REGION           default: ca-central-1 -- must match infra/terraform

set -uo pipefail

usage() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

CLUSTER_NAME="${CLUSTER_NAME:-mfe-pot}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-mfe-pot}"
AWS_REGION="${AWS_REGION:-ca-central-1}"

KIND_CONTEXT="kind-${CLUSTER_NAME}"
EKS_CONTEXT_PREFIX="arn:aws:eks:${AWS_REGION}:"
EKS_CONTEXT_SUFFIX=":cluster/${EKS_CLUSTER_NAME}"
OVERRIDE_DIR="$HOME/.kube/mfe-pot-kctx"

label_for() {
  local ctx="$1"
  if [[ "$ctx" == "$KIND_CONTEXT" ]]; then
    echo "local (kind)"
  elif [[ "$ctx" == ${EKS_CONTEXT_PREFIX}*${EKS_CONTEXT_SUFFIX} ]]; then
    echo "eks"
  else
    echo "other"
  fi
}

resolve_eks_context() {
  kubectl config get-contexts -o name | grep -E "^${EKS_CONTEXT_PREFIX//\//\\/}.*${EKS_CONTEXT_SUFFIX//\//\\/}\$" || {
    echo "no EKS context found matching ${EKS_CONTEXT_PREFIX}*${EKS_CONTEXT_SUFFIX}" >&2
    echo "run: aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION" >&2
    return 1
  }
}

# The real kubeconfig path(s), with any override file this script previously
# injected stripped back out -- prevents the KUBECONFIG list from growing an
# extra override entry every time a switch command gets eval'd again.
base_kubeconfig() {
  local existing="${KUBECONFIG:-$HOME/.kube/config}"
  local IFS=':'
  local -a parts=($existing) kept=()
  for p in "${parts[@]}"; do
    [[ "$p" == "$OVERRIDE_DIR"/* ]] && continue
    kept+=("$p")
  done
  if [[ ${#kept[@]} -eq 0 ]]; then
    echo "$HOME/.kube/config"
  else
    local out
    printf -v out '%s:' "${kept[@]}"
    echo "${out%:}"
  fi
}

switch_shell_local() {
  local ctx="$1" name="$2"
  mkdir -p "$OVERRIDE_DIR"
  local override_file="$OVERRIDE_DIR/$name.yaml"
  cat > "$override_file" <<EOF
apiVersion: v1
kind: Config
current-context: $ctx
EOF
  echo "export KUBECONFIG=\"$override_file:$(base_kubeconfig)\""
  echo "# eval this line, e.g.: eval \"\$(tools/kctx.sh $name)\"" >&2
}

cmd="${1:-show}"
mode="${2:-}"

case "$cmd" in
  show)
    ctx="$(kubectl config current-context 2>/dev/null)" || {
      echo "no current context set" >&2
      exit 1
    }
    echo "$ctx  [$(label_for "$ctx")]"
    ;;

  list)
    kubectl config get-contexts -o name | while read -r ctx; do
      echo "$ctx  [$(label_for "$ctx")]"
    done
    ;;

  local)
    if [[ "$mode" == "--global" ]]; then
      kubectl config use-context "$KIND_CONTEXT"
    else
      switch_shell_local "$KIND_CONTEXT" local
    fi
    ;;

  eks)
    eks_ctx="$(resolve_eks_context)" || exit 1
    if [[ "$mode" == "--global" ]]; then
      kubectl config use-context "$eks_ctx"
    else
      switch_shell_local "$eks_ctx" eks
    fi
    ;;

  *)
    usage >&2
    exit 1
    ;;
esac
