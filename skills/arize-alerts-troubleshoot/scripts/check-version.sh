#!/bin/bash
# check-version.sh -- Compare distribution release version to cluster onprem-metadata.
#
# Usage:
#   check-version.sh --distribution-root <path> [--operator-namespace <ns>] [--context <ctx>]
#
# Exit codes:
#   0  versions match
#   1  versions differ (wrong distribution for this cluster)
#   2  usage / invalid args
#   3  cluster state could not be read (kubectl error, missing ConfigMap, empty field)

set -euo pipefail

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

die() {
  err "$@"
  exit 2
}

usage() {
  cat >&2 <<'EOF'
Usage:
  check-version.sh --distribution-root <path> [--operator-namespace <ns>] [--context <ctx>]

Environment:
  ARIZE_DISTRIBUTION_ROOT / ARIZE_DIST   Default distribution root if flag omitted
  OPERATOR_NS                           Default operator namespace (default: arize-operator)

Compares the numeric release in arize-operator-chart.tgz (Chart.yaml
version / appVersion) to ConfigMap onprem-metadata data.last-applied-release
in the operator namespace.

Also prints the distribution git hash from arize.sh VERSION and the cluster
release-hash when present (informational; match is based on semver).

Exit codes:
  0 match, 1 mismatch, 2 usage, 3 cluster unreadable
EOF
  exit 2
}

require_nonempty() {
  [[ -n "${1:-}" ]] || die "${2}: must not be empty"
}

dist_git_hash_from_arize_sh() {
  local root="$1"
  local file="${root}/arize.sh"
  [[ -f "${file}" ]] || die "Missing ${file}"
  local line
  line="$(grep -E '^VERSION=' "${file}" | head -1 || true)"
  [[ -n "${line}" ]] || die "No VERSION= line in ${file}"
  printf '%s\n' "${line#VERSION=}" | tr -d '"' | tr -d "'"
}

# Numeric release (e.g. 11.43.0) lives in the operator chart, not arize.sh.
# Prefer Chart.yaml appVersion, then version.
dist_semver_from_operator_chart() {
  local root="$1"
  local chart_tgz="${root}/arize-operator-chart.tgz"
  [[ -f "${chart_tgz}" ]] || die "Missing ${chart_tgz}"

  local chart_yaml
  chart_yaml="$(tar -xOf "${chart_tgz}" --wildcards '*/Chart.yaml' 2>/dev/null | head -c 200000 || true)"
  if [[ -z "${chart_yaml}" ]]; then
    # Some tar builds need an exact member name
    local member
    member="$(tar -tzf "${chart_tgz}" | grep -E '(^|/)Chart\.yaml$' | head -1 || true)"
    [[ -n "${member}" ]] || die "No Chart.yaml inside ${chart_tgz}"
    chart_yaml="$(tar -xOf "${chart_tgz}" "${member}")"
  fi

  local app_ver ver
  app_ver="$(printf '%s\n' "${chart_yaml}" | grep -E '^appVersion:' | head -1 | sed -E 's/^appVersion:[[:space:]]*//; s/[\"'\'']//g' | tr -d '[:space:]')"
  ver="$(printf '%s\n' "${chart_yaml}" | grep -E '^version:' | head -1 | sed -E 's/^version:[[:space:]]*//; s/[\"'\'']//g' | tr -d '[:space:]')"

  if [[ -n "${app_ver}" ]]; then
    printf '%s\n' "${app_ver}"
    return 0
  fi
  if [[ -n "${ver}" ]]; then
    printf '%s\n' "${ver}"
    return 0
  fi
  die "Could not parse version/appVersion from Chart.yaml in ${chart_tgz}"
}

kubectl_cli() {
  local ctx_args=()
  if [[ -n "${CONTEXT}" ]]; then
    ctx_args=(--context "${CONTEXT}")
  fi
  kubectl "${ctx_args[@]+"${ctx_args[@]}"}" "$@"
}

# Fetches the ConfigMap once. On failure, KUBECTL_ERR holds kubectl's stderr so
# a connectivity/authorization failure is never reported as a missing version.
fetch_metadata_cm() {
  local ns="$1"
  local err_file out rc=0
  err_file="$(mktemp)"
  out="$(kubectl_cli -n "${ns}" get configmap onprem-metadata -o json 2>"${err_file}")" || rc=$?
  KUBECTL_ERR="$(cat "${err_file}" 2>/dev/null || true)"
  rm -f "${err_file}"
  if [[ ${rc} -ne 0 ]]; then
    return "${rc}"
  fi
  CM_JSON="${out}"
  return 0
}

cm_field() {
  local key="$1"
  jq -r --arg k "${key}" '.data[$k] // ""' <<<"${CM_JSON}"
}

main() {
  local root="${ARIZE_DISTRIBUTION_ROOT:-${ARIZE_DIST:-}}"
  local operator_ns="${OPERATOR_NS:-arize-operator}"
  CONTEXT=""
  CM_JSON=""
  KUBECTL_ERR=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --distribution-root|--docs-root)
        require_nonempty "${2:-}" "$1"
        root="$2"
        shift 2
        ;;
      --operator-namespace)
        require_nonempty "${2:-}" "--operator-namespace"
        operator_ns="$2"
        shift 2
        ;;
      --context)
        require_nonempty "${2:-}" "--context"
        CONTEXT="$2"
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

  require_nonempty "${root}" "distribution root (--distribution-root or ARIZE_DISTRIBUTION_ROOT)"
  root="$(cd "${root}" && pwd)"

  command -v kubectl >/dev/null 2>&1 || die "kubectl not found on PATH"
  command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

  local dist_semver dist_hash
  dist_semver="$(dist_semver_from_operator_chart "${root}")"
  dist_hash="$(dist_git_hash_from_arize_sh "${root}")"

  echo "distribution_root: ${root}"
  echo "distribution_version: ${dist_semver}"
  echo "distribution_git_hash: ${dist_hash}"
  echo "operator_namespace: ${operator_ns}"

  if ! fetch_metadata_cm "${operator_ns}"; then
    echo "cluster_last_applied_release: <unavailable>"
    echo "match: unknown"
    err "kubectl could not read configmap/onprem-metadata in namespace ${operator_ns}."
    if [[ -n "${KUBECTL_ERR}" ]]; then
      err "kubectl said:"
      printf '%s\n' "${KUBECTL_ERR}" | sed 's/^/    /' >&2
    fi
    if printf '%s' "${KUBECTL_ERR}" | grep -qi 'not found'; then
      err "The namespace or ConfigMap does not exist. Confirm the operator namespace (--operator-namespace)."
    else
      err "This is a cluster access problem, not a version problem. Confirm the kube context,"
      err "credentials, VPN/network path, and that this shell is allowed to reach the API server."
    fi
    exit 3
  fi

  local cluster_semver cluster_hash
  cluster_semver="$(cm_field "last-applied-release")"
  cluster_hash="$(cm_field "release-hash")"

  echo "cluster_last_applied_release: ${cluster_semver:-<empty>}"
  echo "cluster_release_hash: ${cluster_hash:-<empty>}"

  if [[ -z "${cluster_semver}" ]]; then
    echo "match: unknown"
    err "ConfigMap onprem-metadata exists but last-applied-release is empty."
    err "This usually means the install has not completed a reconcile yet."
    exit 3
  fi

  if [[ "${dist_semver}" == "${cluster_semver}" ]]; then
    echo "match: true"
    if [[ -n "${cluster_hash}" && "${dist_hash}" != "${cluster_hash}" ]]; then
      err "Informational: release hashes differ (distribution ${dist_hash}, cluster ${cluster_hash})."
      err "Expected when the cluster runs a custom or pre-release build of the same version."
    fi
    exit 0
  fi

  echo "match: false"
  err "Distribution version (${dist_semver}) does not match cluster last-applied-release (${cluster_semver})."
  err "Ask for the unpacked distribution that matches ${cluster_semver} before using local docs."
  exit 1
}

main "$@"
