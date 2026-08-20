#!/bin/bash
# preflight.sh -- Verify tools, distribution root, cluster access, and version match.
#
# Run this before investigating. On failure, print what to ask the user;
# do not continue the skill until the missing input is provided.
#
# Usage:
#   preflight.sh [--distribution-root <path>] [--operator-namespace <ns>] [--context <ctx>]
#
# Exit codes:
#   0  all checks passed
#   1  missing local input (tools, distribution path) — ask the user
#   2  usage
#   3  cluster unreadable (kubectl / onprem-metadata)
#   4  distribution version does not match the cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

die_usage() {
  err "$@"
  exit 2
}

ask() {
  err "ASK THE USER: $*"
}

usage() {
  cat >&2 <<'EOF'
Usage:
  preflight.sh [--distribution-root <path>] [--operator-namespace <ns>] [--context <ctx>]

Checks (stop and prompt on the first failure):
  1. kubectl, curl, jq, python3, tar on PATH
  2. ARIZE_DISTRIBUTION_ROOT is a valid unpack (arize.sh + alerts CSV)
  3. Print the active kube context (agent must confirm it with the user)
  4. kubectl can read configmap/onprem-metadata (cluster access)
  5. distribution semver matches cluster last-applied-release

Exit codes: 0 ok, 1 ask user (local), 2 usage, 3 cluster unreadable, 4 version mismatch
EOF
  exit 2
}

print_kube_context() {
  local ctx_name="$1"
  # stdout so the agent surfaces it; stderr so logs capture it too
  echo "kube_context: ${ctx_name}"
  err "kube_context: ${ctx_name}"
  ask "confirm kube context '${ctx_name}' is the self-hosted cluster you want to diagnose. Do not continue until they say yes. If it is wrong, they should switch context (or set KUBE_CONTEXT / --context) and re-run preflight."
}

main() {
  local root="${ARIZE_DISTRIBUTION_ROOT:-${ARIZE_DIST:-}}"
  local operator_ns="${OPERATOR_NS:-arize-operator}"
  local context="${KUBE_CONTEXT:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --distribution-root|--docs-root)
        [[ -n "${2:-}" ]] || die_usage "$1: must not be empty"
        root="$2"
        shift 2
        ;;
      --operator-namespace)
        [[ -n "${2:-}" ]] || die_usage "--operator-namespace: must not be empty"
        operator_ns="$2"
        shift 2
        ;;
      --context)
        [[ -n "${2:-}" ]] || die_usage "--context: must not be empty"
        context="$2"
        shift 2
        ;;
      --help|-h)
        usage
        ;;
      *)
        err "Unknown argument: $1"
        usage
        ;;
    esac
  done

  local missing=()
  local tool
  for tool in kubectl curl jq python3 tar; do
    command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    ask "install ${missing[*]} (kubectl, curl, jq, python3, tar) and re-run preflight."
    exit 1
  fi
  err "tools: ok (kubectl curl jq python3 tar)"

  if [[ -z "${root}" ]]; then
    ask "the path to the unpacked Arize distribution for this cluster (the folder that contains arize.sh and docs/). Export ARIZE_DISTRIBUTION_ROOT or pass --distribution-root. Do not guess among multiple release folders."
    exit 1
  fi

  if ! python3 "${SCRIPT_DIR}/catalog-lookup.py" \
    --distribution-root "${root}" --print-distribution-root >/dev/null; then
    ask "a valid distribution root. '${root}' is missing arize.sh and/or docs/troubleshooting/selfhosted-alerts-table.csv (or you pointed at the wrong unpack)."
    exit 1
  fi
  root="$(python3 "${SCRIPT_DIR}/catalog-lookup.py" --distribution-root "${root}" --print-distribution-root)"
  err "distribution_root: ${root}"

  local ctx_name
  if [[ -n "${context}" ]]; then
    ctx_name="${context}"
  else
    ctx_name="$(kubectl config current-context 2>/dev/null || true)"
  fi
  if [[ -z "${ctx_name}" ]]; then
    err "kubectl has no current context."
    ask "which kube context points at this self-hosted cluster (kubectl config get-contexts). Set KUBE_CONTEXT or pass --context, and confirm credentials/VPN."
    exit 3
  fi
  print_kube_context "${ctx_name}"

  local cv_args=(--distribution-root "${root}" --operator-namespace "${operator_ns}")
  if [[ -n "${context}" ]]; then
    cv_args+=(--context "${context}")
  fi

  local rc=0
  "${SCRIPT_DIR}/check-version.sh" "${cv_args[@]}" || rc=$?
  case "${rc}" in
    0)
      err "preflight: ok"
      exit 0
      ;;
    1)
      ask "the unpacked distribution that matches cluster last-applied-release (see check-version.sh output). Do not continue with mismatched docs."
      exit 4
      ;;
    2)
      exit 2
      ;;
    3)
      ask "kube access: confirm context '${ctx_name}', credentials, network/VPN, and operator namespace (currently '${operator_ns}' — often arize-operator). ConfigMap onprem-metadata must be readable."
      exit 3
      ;;
    *)
      err "check-version.sh exited ${rc}"
      exit "${rc}"
      ;;
  esac
}

main "$@"
