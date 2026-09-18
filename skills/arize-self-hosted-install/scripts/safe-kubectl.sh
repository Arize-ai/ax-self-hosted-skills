#!/usr/bin/env bash
# Guard direct kubectl validation for the self-hosted installation skill.
# Release-owned arize.sh/Helm installation commands run separately after the
# user confirms the target and mutation.

set -euo pipefail

err() {
  printf '[safe-kubectl] %s\n' "$*" >&2
}

die() {
  err "$@"
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage:
  safe-kubectl.sh context
  KUBE_CONTEXT=<confirmed-context> safe-kubectl.sh <read-only kubectl args>
  safe-kubectl.sh --context <confirmed-context> <read-only kubectl args>

The context command reads local kubeconfig only and prints the context, cluster,
and API server for user confirmation.

Allowed kubectl operations:
  get, describe, logs, top, wait, cluster-info, api-resources, api-versions,
  explain, version, auth whoami, auth can-i, rollout status, port-forward

Mutating operations such as apply, create, delete, edit, patch, replace, scale,
rollout restart, exec, and cp are rejected. Port-forwards bind to 127.0.0.1.
EOF
  exit 1
}

readonly ALLOWED_VERBS_RE='^(get|describe|logs|top|wait|cluster-info|api-resources|api-versions|explain|version|auth|rollout|port-forward)$'
readonly CLUSTER_RESOURCES_RE='^(node|nodes|no|storageclass|storageclasses|sc|namespace|namespaces|ns|persistentvolume|persistentvolumes|pv|customresourcedefinition|customresourcedefinitions|crd|crds)$'

# Flags whose next argument is a value. This is used only to identify the verb
# and resource; kubectl remains responsible for full flag validation.
readonly -a VALUE_FLAGS=(
  -n -l -o -c -f
  --namespace --selector --output --container --filename
  --field-selector --sort-by --template
  --timeout --request-timeout --chunk-size
  --context --kubeconfig --cluster
  --tail --since --since-time --limit-bytes
  --pod-running-timeout --max-log-requests
  --for
)

# These flags can bypass the confirmed kubeconfig target, expose tunnels, or
# access arbitrary API paths. They are not needed by this skill.
readonly -a DENIED_FLAGS=(
  -s
  --server --token --certificate-authority --client-certificate --client-key
  --username --password --as --as-group --as-uid
  --insecure-skip-tls-verify --raw
  --address --bind-address --accept-hosts
)

is_value_flag() {
  local arg="$1" candidate
  for candidate in "${VALUE_FLAGS[@]}"; do
    [[ "${arg}" == "${candidate}" ]] && return 0
  done
  return 1
}

is_denied_flag() {
  local arg="$1" candidate name
  name="${arg%%=*}"
  for candidate in "${DENIED_FLAGS[@]}"; do
    [[ "${name}" == "${candidate}" ]] && return 0
  done
  return 1
}

has_context() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --context|--context=*) return 0 ;;
    esac
  done
  return 1
}

has_namespace() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      -n|--namespace|--namespace=*|-n?*|-A|--all-namespaces) return 0 ;;
    esac
  done
  return 1
}

has_client_only() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --client|--client=*) return 0 ;;
    esac
  done
  return 1
}

scan_positionals() {
  local skip_next=false found_verb=false arg
  VERB=""
  SUBJECT=""

  for arg in "$@"; do
    if [[ "${skip_next}" == true ]]; then
      skip_next=false
      continue
    fi
    if is_value_flag "${arg}"; then
      skip_next=true
      continue
    fi
    if [[ "${arg}" == -* ]]; then
      continue
    fi
    if [[ "${found_verb}" == false ]]; then
      VERB="${arg}"
      found_verb=true
    elif [[ -z "${SUBJECT}" ]]; then
      SUBJECT="${arg}"
    fi
  done
}

require_namespace_for_namespaced_operation() {
  local resource base
  case "${VERB}" in
    logs|wait|rollout|port-forward)
      has_namespace "$@" || die "Namespace required for '${VERB}'. Use -n <namespace>."
      ;;
    get|describe)
      resource="${SUBJECT%%,*}"
      base="${resource%%/*}"
      if [[ ! "${base}" =~ ${CLUSTER_RESOURCES_RE} ]]; then
        has_namespace "$@" || die \
          "Namespace required for '${VERB} ${SUBJECT}'. Use -n <namespace> or -A."
      fi
      ;;
    top)
      resource="${SUBJECT%%,*}"
      base="${resource%%/*}"
      if [[ "${base}" != "node" && "${base}" != "nodes" && "${base}" != "no" ]]; then
        has_namespace "$@" || die "Namespace required for 'top ${SUBJECT}'."
      fi
      ;;
  esac
}

show_context() {
  [[ $# -eq 1 ]] || die "'context' does not accept additional arguments."
  command -v kubectl >/dev/null 2>&1 || die "kubectl not found on PATH"

  local context details cluster server
  context="${KUBE_CONTEXT:-$(kubectl config current-context)}"
  [[ -n "${context}" ]] || die "No kubeconfig context is selected."

  details="$(
    kubectl config view --context "${context}" --minify \
      -o jsonpath='{.clusters[0].name}{"\n"}{.clusters[0].cluster.server}{"\n"}'
  )"
  cluster="${details%%$'\n'*}"
  server="${details#*$'\n'}"

  printf 'kube_context: %s\ncluster_name: %s\napi_server: %s\n' \
    "${context}" "${cluster}" "${server}"
}

main() {
  [[ $# -gt 0 ]] || usage
  case "${1}" in
    --help|-h) usage ;;
    context)
      show_context "$@"
      return
      ;;
  esac

  command -v kubectl >/dev/null 2>&1 || die "kubectl not found on PATH"

  local arg
  for arg in "$@"; do
    is_denied_flag "${arg}" && die "Flag '${arg%%=*}' is not allowed."
  done

  scan_positionals "$@"
  [[ -n "${VERB}" ]] || die "No kubectl verb found."
  [[ "${VERB}" =~ ${ALLOWED_VERBS_RE} ]] || die \
    "Operation '${VERB}' is not allowed; only validation and local tunnels are permitted."

  case "${VERB}" in
    auth)
      [[ "${SUBJECT}" == "whoami" || "${SUBJECT}" == "can-i" ]] || die \
        "Only 'auth whoami' and 'auth can-i' are allowed."
      ;;
    rollout)
      [[ "${SUBJECT}" == "status" ]] || die \
        "Only 'rollout status' is allowed; rollout mutations are forbidden."
      ;;
    cluster-info)
      [[ -z "${SUBJECT}" ]] || die "Only plain 'cluster-info' is allowed."
      ;;
  esac

  if [[ "${VERB}" == "version" ]] && has_client_only "$@"; then
    exec kubectl "$@"
  fi

  if [[ -z "${KUBE_CONTEXT:-}" ]] && ! has_context "$@"; then
    die "Set KUBE_CONTEXT to the exact user-confirmed context before contacting the API."
  fi

  require_namespace_for_namespaced_operation "$@"

  local extra=() tunnel_safety=()
  if [[ -n "${KUBE_CONTEXT:-}" ]] && ! has_context "$@"; then
    extra=(--context "${KUBE_CONTEXT}")
  fi
  if [[ "${VERB}" == "port-forward" ]]; then
    tunnel_safety=(--address=127.0.0.1)
  fi

  exec kubectl ${extra[@]+"${extra[@]}"} "$@" \
    ${tunnel_safety[@]+"${tunnel_safety[@]}"}
}

main "$@"
