#!/usr/bin/env bash
# open-ports.sh -- Start read-only port-forwards for self-hosted troubleshooting.
#
# Usage:
#   open-ports.sh --namespace <ns> [--context <ctx>] [--prometheus] [--alertmanager] [--kube-proxy]
#   open-ports.sh --namespace <ns> --all
#   open-ports.sh --status
#   open-ports.sh --stop
#
# Defaults: prometheus + alertmanager.
# PID file and kubectl logs live under ${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}
#
# Exit codes:
#   0  all requested forwards are serving
#   1  at least one forward failed to come up (see the printed log)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
SAFE_KUBECTL="${SCRIPT_DIR}/safe-kubectl.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  open-ports.sh --namespace <ns> [--context <ctx>] [--prometheus] [--alertmanager] [--kube-proxy]
  open-ports.sh --namespace <ns> --all
  open-ports.sh --status
  open-ports.sh --stop

Environment:
  ARIZE_NAMESPACE   Default namespace if --namespace omitted
  ARIZE_SKILL_TMP   Scratch dir (default /tmp/arize-alerts-troubleshoot)

Examples:
  open-ports.sh --namespace arize
  open-ports.sh --namespace arize --all
  open-ports.sh --status
  open-ports.sh --stop
EOF
  exit 1
}

TMP_DIR="${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}"
PID_FILE="${TMP_DIR}/port-forwards.pid"
META_FILE="${TMP_DIR}/port-forwards.meta"
mkdir -p "${TMP_DIR}"

# A listener answering HTTP on the port means curl connected (any status code).
port_answers() {
  local port="$1"
  curl -s -o /dev/null --max-time 3 "http://127.0.0.1:${port}/" >/dev/null 2>&1
}

# Confirm an existing listener is the service we intend to query. This prevents
# a local dev server on 9090/9093/8080 from being mistaken for a live tunnel.
service_answers() {
  local label="$1"
  local port="$2"
  local path
  case "${label}" in
    prometheus)   path="/prometheus/api/v1/status/config" ;;
    alertmanager) path="/alertmanager/api/v2/status" ;;
    kube-proxy)   path="/version" ;;
    *)            return 1 ;;
  esac
  curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:${port}${path}" \
    >/dev/null 2>&1
}

stop_forwards() {
  if [[ -f "${PID_FILE}" ]]; then
    while read -r pid; do
      [[ -z "${pid}" ]] && continue
      if kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null || true
        err "Stopped PID ${pid}"
      fi
    done < "${PID_FILE}"
    rm -f "${PID_FILE}" "${META_FILE}"
  else
    err "No PID file at ${PID_FILE}"
    rm -f "${META_FILE}"
  fi
}

# Drop dead PIDs; keep live ones so a re-run that adds another forward
# does not orphan earlier tunnels from --stop.
prune_pid_file() {
  local tmp alive=0
  tmp="$(mktemp "${TMP_DIR}/port-forwards.XXXXXX")"
  if [[ -f "${PID_FILE}" ]]; then
    while read -r pid; do
      [[ -z "${pid}" ]] && continue
      if kill -0 "${pid}" 2>/dev/null; then
        echo "${pid}" >> "${tmp}"
        alive=$((alive + 1))
      fi
    done < "${PID_FILE}"
  fi
  if [[ ${alive} -gt 0 ]]; then
    mv "${tmp}" "${PID_FILE}"
  else
    rm -f "${tmp}" "${PID_FILE}" "${META_FILE}"
  fi
}

status_forwards() {
  local label port label_port
  for label_port in "prometheus:9090" "alertmanager:9093" "kube-proxy:8080"; do
    label="${label_port%%:*}"
    port="${label_port##*:}"
    if service_answers "${label}" "${port}"; then
      echo "port ${port} (${label}): serving"
    elif port_answers "${port}"; then
      echo "port ${port}: listener (identity probe failed)"
    else
      echo "port ${port}: no listener"
    fi
  done
  if [[ -f "${META_FILE}" ]]; then
    echo "meta_file: ${META_FILE}"
    sed 's/^/  /' "${META_FILE}"
  fi
  if [[ -f "${PID_FILE}" ]]; then
    echo "pid_file: ${PID_FILE}"
    while read -r pid; do
      [[ -z "${pid}" ]] && continue
      if kill -0 "${pid}" 2>/dev/null; then
        echo "  pid ${pid}: alive"
      else
        echo "  pid ${pid}: dead"
      fi
    done < "${PID_FILE}"
  fi
}

# Waits for the forward to serve. Reports kubectl's own error when it exits
# early, so an access failure is never mistaken for a slow tunnel.
wait_for_forward() {
  local label="$1"
  local pid="$2"
  local port="$3"
  local log="$4"
  local i

  for ((i = 0; i < 30; i++)); do
    if ! kill -0 "${pid}" 2>/dev/null; then
      err "${label}: port-forward exited immediately (PID ${pid}). kubectl output:"
      sed 's/^/    /' "${log}" >&2 || true
      return 1
    fi
    if service_answers "${label}" "${port}"; then
      err "${label}: serving on 127.0.0.1:${port} (PID ${pid})"
      return 0
    fi
    sleep 1
  done

  err "${label}: no response on 127.0.0.1:${port} after 30s. kubectl output:"
  sed 's/^/    /' "${log}" >&2 || true
  return 1
}

# Start a long-lived tunnel in its own session and echo its PID.
#
# nohup only ignores SIGHUP. Agent harnesses commonly kill the launching
# shell's entire process group when a command returns, which reaps the tunnel
# regardless of nohup/disown. setsid() moves it to a fresh session so that
# signal never reaches it; execvp keeps the PID stable so callers can still
# poll it. python3 is used because macOS ships no setsid(1).
spawn_detached() {
  local log="$1"
  shift
  nohup python3 -c '
import os, sys
try:
    os.setsid()
except OSError:
    pass  # already a session leader
os.execvp(sys.argv[1], sys.argv[1:])
' "$@" </dev/null >>"${log}" 2>&1 &
  local pid=$!
  disown "${pid}" 2>/dev/null || true
  printf '%s' "${pid}"
}

write_forward_meta() {
  {
    echo "namespace=${NAMESPACE}"
    echo "context=${EFFECTIVE_CONTEXT:-}"
  } > "${META_FILE}"
}

tunnel_meta_matches() {
  [[ -f "${META_FILE}" ]] || return 1
  local saved_ns="" saved_ctx=""
  while IFS='=' read -r key value; do
    case "${key}" in
      namespace) saved_ns="${value}" ;;
      context) saved_ctx="${value}" ;;
    esac
  done < "${META_FILE}"
  [[ "${saved_ns}" == "${NAMESPACE}" ]] \
    && [[ "${saved_ctx}" == "${EFFECTIVE_CONTEXT:-}" ]]
}

require_matching_tunnel_meta() {
  local label="$1"
  local port="$2"

  if [[ ! -f "${META_FILE}" ]]; then
    die "${label}: port ${port} serves the expected API, but no tunnel metadata is recorded; namespace/context cannot be verified." \
      "Stop the process listening on port ${port} manually and retry. '--stop' can only stop PIDs recorded in ${PID_FILE}."
  fi

  if ! tunnel_meta_matches; then
    if [[ -f "${PID_FILE}" ]]; then
      die "${label}: port ${port} belongs to a different namespace/context. Run '--stop' first."
    fi
    die "${label}: port ${port} metadata does not match, but no managed PID is recorded." \
      "Stop the process listening on port ${port} manually and retry."
  fi
}

remove_pid() {
  local target_pid="$1"
  local tmp
  tmp="$(mktemp "${TMP_DIR}/port-forwards.XXXXXX")"
  if [[ -f "${PID_FILE}" ]]; then
    while read -r pid; do
      [[ -z "${pid}" || "${pid}" == "${target_pid}" ]] && continue
      echo "${pid}" >> "${tmp}"
    done < "${PID_FILE}"
  fi
  if [[ -s "${tmp}" ]]; then
    mv "${tmp}" "${PID_FILE}"
  else
    rm -f "${tmp}" "${PID_FILE}" "${META_FILE}"
  fi
}

start_pf() {
  local label="$1"
  local port="$2"
  shift 2
  local args=("$@")
  local log="${TMP_DIR}/${label}-port-forward.log"

  if port_answers "${port}"; then
    if service_answers "${label}" "${port}"; then
      require_matching_tunnel_meta "${label}" "${port}"
      err "${label}: port ${port} already serving the expected API; reusing it."
      return 0
    fi
    die "${label}: port ${port} is occupied, but its identity probe failed. Stop the other listener, or run '--stop' to tear down forwards from a previous run."
  fi

  : > "${log}"
  local pid
  pid="$(spawn_detached "${log}" "${SAFE_KUBECTL}" \
    ${KUBECTL_CONTEXT_ARGS[@]+"${KUBECTL_CONTEXT_ARGS[@]}"} \
    -n "${NAMESPACE}" port-forward "${args[@]}")"
  echo "${pid}" >> "${PID_FILE}"
  err "${label}: log ${log}"

  if wait_for_forward "${label}" "${pid}" "${port}" "${log}"; then
    write_forward_meta
    return 0
  fi
  kill "${pid}" 2>/dev/null || true
  remove_pid "${pid}"
  return 1
}

start_proxy() {
  local log="${TMP_DIR}/kube-proxy.log"

  if port_answers 8080; then
    if service_answers "kube-proxy" 8080; then
      require_matching_tunnel_meta "kube-proxy" 8080
      err "kube-proxy: port 8080 already serving the expected API; reusing it."
      return 0
    fi
    die "kube-proxy: port 8080 is occupied, but its identity probe failed. Stop the other listener, or run '--stop' to tear down forwards from a previous run."
  fi

  : > "${log}"
  local pid
  pid="$(spawn_detached "${log}" "${SAFE_KUBECTL}" \
    ${KUBECTL_CONTEXT_ARGS[@]+"${KUBECTL_CONTEXT_ARGS[@]}"} \
    proxy --port=8080)"
  echo "${pid}" >> "${PID_FILE}"
  err "kube-proxy: log ${log}"

  if wait_for_forward "kube-proxy" "${pid}" 8080 "${log}"; then
    write_forward_meta
    return 0
  fi
  kill "${pid}" 2>/dev/null || true
  remove_pid "${pid}"
  return 1
}

main() {
  local namespace="${ARIZE_NAMESPACE:-}"
  local context=""
  local do_prom=""
  local do_am=""
  local do_proxy=""
  local stop_only=""
  local status_only=""
  local any_flag=""
  local failures=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace)
        require_nonempty "${2:-}" "--namespace"
        namespace="$2"
        shift 2
        ;;
      --context)
        require_nonempty "${2:-}" "--context"
        context="$2"
        shift 2
        ;;
      --prometheus)
        do_prom=1
        any_flag=1
        shift
        ;;
      --alertmanager)
        do_am=1
        any_flag=1
        shift
        ;;
      --kube-proxy)
        do_proxy=1
        any_flag=1
        shift
        ;;
      --all)
        do_prom=1
        do_am=1
        do_proxy=1
        any_flag=1
        shift
        ;;
      --stop)
        stop_only=1
        shift
        ;;
      --status)
        status_only=1
        shift
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

  if [[ -n "${stop_only}" ]]; then
    stop_forwards
    exit 0
  fi

  if [[ -n "${status_only}" ]]; then
    status_forwards
    exit 0
  fi

  require_nonempty "${namespace}" "namespace (--namespace or ARIZE_NAMESPACE)"
  NAMESPACE="${namespace}"

  command -v kubectl >/dev/null 2>&1 || die "kubectl not found on PATH"
  command -v curl >/dev/null 2>&1 || die "curl not found on PATH"
  command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"
  [[ -x "${SAFE_KUBECTL}" ]] || die "safe-kubectl.sh is not executable: ${SAFE_KUBECTL}"

  KUBECTL_CONTEXT_ARGS=()
  if [[ -n "${context}" ]]; then
    KUBECTL_CONTEXT_ARGS=(--context "${context}")
  fi

  EFFECTIVE_CONTEXT="${context:-${KUBE_CONTEXT:-}}"
  if [[ -z "${EFFECTIVE_CONTEXT}" ]]; then
    EFFECTIVE_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
  fi

  if [[ -z "${any_flag}" ]]; then
    do_prom=1
    do_am=1
  fi

  prune_pid_file

  if [[ -n "${do_prom}" ]]; then
    if start_pf "prometheus" 9090 svc/prometheus 9090:9090; then
      # On-prem Prometheus serves the API under /prometheus (bare / redirects).
      echo "export PROM=http://localhost:9090/prometheus"
    else
      failures=$((failures + 1))
    fi
  fi
  if [[ -n "${do_am}" ]]; then
    if start_pf "alertmanager" 9093 svc/alertmanager 9093:9093; then
      # On-prem Alertmanager serves the API under /alertmanager.
      echo "export AM=http://localhost:9093/alertmanager"
    else
      failures=$((failures + 1))
    fi
  fi
  if [[ -n "${do_proxy}" ]]; then
    if start_proxy; then
      echo "export KUBE_PROXY=http://localhost:8080"
    else
      failures=$((failures + 1))
    fi
  fi

  err "PID file: ${PID_FILE} (run with --stop to tear down, --status to re-check)"

  if [[ ${failures} -gt 0 ]]; then
    err "${failures} forward(s) failed. Fix cluster access before querying PROM/AM."
    exit 1
  fi
}

main "$@"
