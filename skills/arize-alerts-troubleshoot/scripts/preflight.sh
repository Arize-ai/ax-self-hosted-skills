#!/usr/bin/env bash
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
#   5  this shell has no network path to the API server (e.g. agent sandbox)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
SAFE_KUBECTL="${SCRIPT_DIR}/safe-kubectl.sh"

# Failures meaning "this shell cannot reach the API server" rather than
# "credentials or namespace are wrong". Sandboxed agent shells hit these even
# when the operator's own terminal works fine.
readonly NETWORK_PATH_ERR_RE='no such host|i/o timeout|Timeout|deadline exceeded|connection refused|network is unreachable|no route to host|proxyconnect|dial tcp'

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
  4. This shell can actually reach the Kubernetes API server
  5. kubectl can read configmap/onprem-metadata (cluster access)
  6. distribution semver matches cluster last-applied-release

Exit codes: 0 ok, 1 ask user (local), 2 usage, 3 cluster unreadable,
            4 version mismatch, 5 no network path from this shell (sandbox)
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

# Probes the API server directly so a blocked shell is never reported as a
# credential, namespace, or cluster-health problem.
check_api_reachable() {
  local err_file rc=0
  err_file="$(mktemp)"
  "${SAFE_KUBECTL}" ${KUBECTL_ARGS[@]+"${KUBECTL_ARGS[@]}"} --request-timeout=15s \
    get --raw /version >/dev/null 2>"${err_file}" || rc=$?
  API_ERR="$(cat "${err_file}" 2>/dev/null || true)"
  rm -f "${err_file}"
  return "${rc}"
}

report_unreachable_api() {
  local ctx_name="$1"
  local api_host="$2"

  err "kubectl could not reach the Kubernetes API server (${api_host:-unknown endpoint})."
  if [[ -n "${API_ERR}" ]]; then
    err "kubectl said:"
    printf '%s\n' "${API_ERR}" | sed 's/^/    /' >&2
  fi

  if printf '%s' "${API_ERR}" | grep -qE "${NETWORK_PATH_ERR_RE}"; then
    err "This is a NETWORK PATH failure from THIS shell — not credentials, not"
    err "the namespace, and not cluster health. Do not report it as any of those."
    err "If 'kubectl get ns' works in the operator's own terminal, this shell is"
    err "sandboxed or firewalled. Re-run with unrestricted network access"
    err "(disable the agent shell sandbox), then retry preflight."
    ask "first re-run this from a shell with full network access. Only if it still fails there should they check VPN/credentials for context '${ctx_name}'."
    exit 5
  fi

  ask "kube access for context '${ctx_name}': re-authenticate (credentials may be expired) and confirm the cluster endpoint is reachable."
  exit 3
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
  [[ -x "${SAFE_KUBECTL}" ]] || {
    err "safe-kubectl.sh is not executable: ${SAFE_KUBECTL}"
    exit 1
  }

  if [[ -z "${root}" ]]; then
    ask "the path to the unpacked Arize distribution for this cluster (the folder that contains arize.sh and docs/). Export ARIZE_DISTRIBUTION_ROOT or pass --distribution-root. Do not guess among multiple release folders."
    exit 1
  fi

  local resolved_root
  if ! resolved_root="$(python3 "${SCRIPT_DIR}/catalog-lookup.py" \
    --distribution-root "${root}" --print-distribution-root)"; then
    ask "a valid distribution root. '${root}' is missing arize.sh and/or docs/troubleshooting/selfhosted-alerts-table.csv (or you pointed at the wrong unpack)."
    exit 1
  fi
  root="${resolved_root}"
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

  KUBECTL_ARGS=()
  if [[ -n "${context}" ]]; then
    KUBECTL_ARGS=(--context "${context}")
  fi

  local api_host
  api_host="$(kubectl ${KUBECTL_ARGS[@]+"${KUBECTL_ARGS[@]}"} config view --minify \
    -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"

  API_ERR=""
  if ! check_api_reachable; then
    report_unreachable_api "${ctx_name}" "${api_host}"
  fi
  err "api_server: reachable (${api_host})"

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
      # The API server already answered above, so this is a namespace/RBAC or
      # not-yet-reconciled problem — not connectivity.
      ask "the operator namespace: ConfigMap onprem-metadata was not readable in '${operator_ns}' even though the API server is reachable. Confirm the operator namespace (often arize-operator) and that your user can read ConfigMaps there."
      exit 3
      ;;
    *)
      err "check-version.sh exited ${rc}"
      exit "${rc}"
      ;;
  esac
}

main "$@"
