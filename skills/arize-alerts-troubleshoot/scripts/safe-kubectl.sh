#!/usr/bin/env bash
# safe-kubectl.sh -- Read-only kubectl wrapper for this skill.
#
# Agents must use this instead of raw kubectl. Mutating verbs are rejected.
# Namespace is required for namespaced verbs (-n / --namespace / -A).
#
# Usage:
#   safe-kubectl.sh [-n <namespace>|-A] <verb> [args...]
#   safe-kubectl.sh --context <ctx> -n <namespace> get pods
#   KUBE_CONTEXT=<ctx> safe-kubectl.sh -n <namespace> logs deploy/<name> --tail=200
#
# Context: --context, $KUBE_CONTEXT, or kubectl's current-context.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Keep in sync with the SKILL.md kubectl allowlist.
readonly ALLOWED_VERBS_RE="^(get|describe|logs|log|top|explain|api-resources|api-versions|version|cluster-info|port-forward|proxy)$"

# Cluster-scoped verbs that do not require -n / -A.
readonly CLUSTER_VERBS_RE="^(explain|api-resources|api-versions|version|cluster-info|proxy)$"

# Flags that take a separate value argument (next positional).
readonly -a VALUE_FLAGS=(
  -n -l -o -c
  --namespace --selector --output --container
  --field-selector --sort-by --template
  --timeout --request-timeout --chunk-size
  --context --kubeconfig --cluster
  --tail --since --since-time --limit-bytes
  --pod-running-timeout --max-log-requests
  --raw
)

# Long flags that do not take a separate value. Any other bare --flag is rejected
# so its value is not mistaken for the kubectl verb.
readonly -a BOOLEAN_LONG_FLAGS=(
  --previous
  --all-namespaces
  --ignore-not-found
  --show-labels
  --show-managed-fields
  --watch
  --watch-only
)

usage() {
  cat >&2 <<'EOF'
Usage:
  safe-kubectl.sh [-n <namespace>|-A] <verb> [args...]
  safe-kubectl.sh --context <ctx> -n <namespace> get pods

Allowed verbs:
  get, describe, logs, top, explain, api-resources, api-versions,
  version, cluster-info, port-forward, proxy

Namespace (-n / --namespace / -A) is required except for cluster-scoped
verbs (version, api-resources, api-versions, cluster-info, explain, proxy).

Context comes from --context, $KUBE_CONTEXT, or kubectl's current-context.
EOF
  exit 1
}

# Long flags blocked for port-forward/proxy — binding beyond localhost.
readonly -a DENIED_LONG_FLAGS=(
  --address
  --accept-hosts
  --bind-address
)

is_value_flag() {
  local arg="$1" flag
  for flag in "${VALUE_FLAGS[@]}"; do
    [[ "${arg}" == "${flag}" ]] && return 0
  done
  return 1
}

is_boolean_long_flag() {
  local arg="$1" flag
  for flag in "${BOOLEAN_LONG_FLAGS[@]}"; do
    [[ "${arg}" == "${flag}" ]] && return 0
  done
  return 1
}

is_denied_long_flag() {
  local arg="$1" flag
  for flag in "${DENIED_LONG_FLAGS[@]}"; do
    [[ "${arg}" == "${flag}" ]] && return 0
  done
  return 1
}

is_allowed_long_flag() {
  local arg="$1"
  is_denied_long_flag "${arg}" && return 1
  is_value_flag "${arg}" && return 0
  is_boolean_long_flag "${arg}" && return 0
  return 1
}

# Find the kubectl verb, skipping flags and their values.
find_verb() {
  local skip_next=false
  local arg
  for arg in "$@"; do
    if [[ "${skip_next}" == true ]]; then
      skip_next=false
      continue
    fi

    if is_value_flag "${arg}"; then
      skip_next=true
      continue
    fi

    if [[ "${arg}" == --*=* ]]; then
      local flag_name="${arg%%=*}"
      if is_denied_long_flag "${flag_name}"; then
        die "Flag '${flag_name}' is not allowed — it can bind tunnels beyond localhost."
      fi
      if ! is_allowed_long_flag "${flag_name}"; then
        die "Unsupported flag '${flag_name}'."
      fi
      continue
    fi

    if [[ "${arg}" == --* ]]; then
      if is_denied_long_flag "${arg}"; then
        die "Flag '${arg}' is not allowed — it can bind tunnels beyond localhost."
      fi
      if is_boolean_long_flag "${arg}"; then
        continue
      fi
      die "Unsupported flag '${arg}'. Use --flag=value form for flags that take a value."
    fi

    if [[ "${arg}" == -* ]]; then
      continue
    fi

    echo "${arg}"
    return 0
  done
}

has_namespace() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      -n|--namespace|--namespace=*|-n=*|--all-namespaces|-A)
        return 0
        ;;
    esac
  done
  return 1
}

has_context_flag() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --context|--context=*)
        return 0
        ;;
    esac
  done
  return 1
}

has_raw_flag() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --raw|--raw=*)
        return 0
        ;;
    esac
  done
  return 1
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
  fi
  case "${1}" in
    --help|-h) usage ;;
  esac

  command -v kubectl >/dev/null 2>&1 || die "kubectl not found on PATH"

  local verb
  verb="$(find_verb "$@")"
  if [[ -z "${verb}" ]]; then
    die "No verb found. Provide a read-only verb (get, describe, logs, top, etc.)."
  fi

  if [[ ! "${verb}" =~ ${ALLOWED_VERBS_RE} ]]; then
    die "Verb '${verb}' is not allowed. Only read-only operations permitted." \
      "Allowed: get, describe, logs, top, explain, api-resources," \
      "api-versions, version, cluster-info, port-forward, proxy"
  fi

  if [[ ! "${verb}" =~ ${CLUSTER_VERBS_RE} ]] \
    && ! has_namespace "$@" \
    && ! has_raw_flag "$@"; then
    die "Namespace is required. Use -n <namespace> or -A for all namespaces."
  fi

  local extra=()
  if [[ -n "${KUBE_CONTEXT:-}" ]] && ! has_context_flag "$@"; then
    extra=(--context "${KUBE_CONTEXT}")
  fi

  exec kubectl ${extra[@]+"${extra[@]}"} "$@"
}

main "$@"
