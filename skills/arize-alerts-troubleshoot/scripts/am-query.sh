#!/usr/bin/env bash
# am-query.sh -- Query Alertmanager HTTP API (read-only).
#
# Usage:
#   am-query.sh --url <alertmanager-url> --firing [--json]
#   am-query.sh --url <alertmanager-url> --dump
#   am-query.sh --url <alertmanager-url> --filter '<matcher>'
#   am-query.sh --url <alertmanager-url> --status
#   am-query.sh --url <alertmanager-url> --silences
#   am-query.sh --url <alertmanager-url> --groups
#
# AM_URL or AM may be set instead of --url.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  am-query.sh --url <alertmanager-url> --firing [--json]
  am-query.sh --url <alertmanager-url> --dump
  am-query.sh --url <alertmanager-url> --filter '<matcher>'
  am-query.sh --url <alertmanager-url> --status
  am-query.sh --url <alertmanager-url> --silences
  am-query.sh --url <alertmanager-url> --groups

Environment:
  AM_URL or AM       Default Alertmanager base URL if --url is omitted
  CURL_INSECURE=1    Force curl -k for HTTPS (also enabled via --insecure)

Examples:
  am-query.sh --url http://localhost:9093/alertmanager --firing
  AM=http://localhost:9093/alertmanager am-query.sh --firing --json
  # Bare http://localhost:9093 also works — the script detects /alertmanager when needed.
  # HTTPS to real ingress verifies TLS by default; use --insecure only if needed.
EOF
  exit 1
}

# On-prem Alertmanager is often served under /alertmanager.
resolve_am_base() {
  local base="$1"
  local insecure="${2:-0}"
  local flags
  flags="$(curl_flags "${base}" "${insecure}")"
  local code
  # shellcheck disable=SC2086
  code="$(curl ${flags} -o /dev/null -w '%{http_code}' --max-time 10 \
    "${base}/api/v2/status" 2>/dev/null || echo "000")"

  if [[ "${code}" == "200" ]]; then
    printf '%s\n' "${base}"
    return 0
  fi

  if [[ "${base}" != */alertmanager ]]; then
    local alt="${base}/alertmanager"
    local alt_code
    # shellcheck disable=SC2086
    alt_code="$(curl ${flags} -o /dev/null -w '%{http_code}' --max-time 10 \
      "${alt}/api/v2/status" 2>/dev/null || echo "000")"
    if [[ "${alt_code}" == "200" ]]; then
      err "Alertmanager is under ${alt} (got HTTP ${code} at ${base}/api/v2/status); using subpath."
      printf '%s\n' "${alt}"
      return 0
    fi
  fi

  die "Alertmanager API not reachable at ${base}/api/v2/status (HTTP ${code}). If the UI redirects to /alertmanager, set --url to http://host:port/alertmanager"
}

am_get() {
  local base="$1"
  local path="$2"
  local insecure="${3:-0}"
  local flags
  flags="$(curl_flags "${base}" "${insecure}")"

  local body
  # Intentionally unquoted flags: expands to -s or -sk.
  # shellcheck disable=SC2086
  if ! body="$(curl ${flags} --fail --max-time 30 "${base}${path}")"; then
    die "Alertmanager request failed: ${base}${path}"
  fi
  printf '%s\n' "${body}"
}

summarize_alerts() {
  local raw="$1"
  local as_json="${2:-}"

  if [[ "${as_json}" == "json" ]]; then
    jq '[.[] | {
      alertname: .labels.alertname,
      severity: (.labels.severity // .labels.channel // null),
      component: (.labels.component // null),
      summary: (.annotations.summary // null),
      description: (.annotations.description // null),
      startsAt: .startsAt,
      endsAt: .endsAt,
      labels: .labels
    }]' <<<"${raw}"
    return
  fi

  jq -r '
    .[] |
    [
      (.labels.alertname // "-"),
      (.labels.severity // .labels.channel // "-"),
      (.labels.component // "-"),
      (.startsAt // "-"),
      ((.annotations.summary // "") | gsub("\n"; " "))
    ] | @tsv
  ' <<<"${raw}" \
    | (printf 'ALERTNAME\tSEVERITY\tCOMPONENT\tSTARTS_AT\tSUMMARY\n'; cat) \
    | column -t -s $'\t' 2>/dev/null || cat
}

main() {
  local am_url="${AM_URL:-${AM:-}}"
  local mode=""
  local filter=""
  local as_json=""
  local insecure=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url)
        require_nonempty "${2:-}" "--url"
        am_url="$2"
        shift 2
        ;;
      --firing|--dump|--status|--silences|--groups)
        mode="$1"
        shift
        ;;
      --filter)
        require_nonempty "${2:-}" "--filter"
        mode="--filter"
        filter="$2"
        shift 2
        ;;
      --json)
        as_json="json"
        shift
        ;;
      --insecure)
        insecure=1
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

  require_nonempty "${am_url}" "Alertmanager URL (--url, AM_URL, or AM)"
  require_nonempty "${mode}" "mode (--firing, --dump, --filter, --status, --silences, --groups)"
  am_url="$(normalize_url "${am_url}")"
  am_url="$(resolve_am_base "${am_url}" "${insecure}")"

  local raw
  case "${mode}" in
    --firing)
      raw="$(am_get "${am_url}" "/api/v2/alerts?active=true" "${insecure}")"
      summarize_alerts "${raw}" "${as_json}"
      ;;
    --dump)
      am_get "${am_url}" "/api/v2/alerts" "${insecure}"
      ;;
    --filter)
      raw="$(am_get "${am_url}" "/api/v2/alerts?filter=$(printf '%s' "${filter}" | jq -sRr @uri)" "${insecure}")"
      summarize_alerts "${raw}" "${as_json}"
      ;;
    --status)
      am_get "${am_url}" "/api/v2/status" "${insecure}" | jq .
      ;;
    --silences)
      am_get "${am_url}" "/api/v2/silences" "${insecure}" | jq .
      ;;
    --groups)
      am_get "${am_url}" "/api/v2/alerts/groups" "${insecure}" | jq .
      ;;
    *)
      die "Unhandled mode: ${mode}"
      ;;
  esac
}

main "$@"
