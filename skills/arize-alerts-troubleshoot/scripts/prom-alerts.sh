#!/bin/bash
# prom-alerts.sh -- Query firing alerts from Prometheus (read-only).
#
# Usage:
#   prom-alerts.sh --url <prometheus-url> --firing [--json]
#   prom-alerts.sh --url <prometheus-url> --rules
#   prom-alerts.sh --url <prometheus-url> --query '<promql>'
#
# PROM_URL or PROM may be set instead of --url.

set -euo pipefail

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

die() {
  err "$@"
  exit 1
}

require_nonempty() {
  [[ -n "${1:-}" ]] || die "${2}: must not be empty"
}

usage() {
  cat >&2 <<'EOF'
Usage:
  prom-alerts.sh --url <prometheus-url> --firing [--json]
  prom-alerts.sh --url <prometheus-url> --rules
  prom-alerts.sh --url <prometheus-url> --query '<promql>'

Environment:
  PROM_URL or PROM   Default Prometheus base URL if --url is omitted

Examples:
  prom-alerts.sh --url http://localhost:9090/prometheus --firing
  PROM=http://localhost:9090/prometheus prom-alerts.sh --firing --json
  # Bare http://localhost:9090 also works — the script detects /prometheus when needed.
EOF
  exit 1
}

curl_flags() {
  local url="$1"
  if [[ "${url}" == https://* ]]; then
    echo "-sk"
  else
    echo "-s"
  fi
}

normalize_url() {
  local url="$1"
  echo "${url%/}"
}

# On-prem Prometheus is often served under /prometheus (bare / returns 302/404).
# If the caller passed a host root, rewrite to include the subpath when needed.
resolve_prom_base() {
  local base="$1"
  local flags
  flags="$(curl_flags "${base}")"
  local code
  # shellcheck disable=SC2086
  code="$(curl ${flags} -o /dev/null -w '%{http_code}' --max-time 10 \
    "${base}/api/v1/query?query=up" 2>/dev/null || echo "000")"

  if [[ "${code}" == "200" ]]; then
    printf '%s\n' "${base}"
    return 0
  fi

  if [[ "${base}" != */prometheus ]]; then
    local alt="${base}/prometheus"
    local alt_code
    # shellcheck disable=SC2086
    alt_code="$(curl ${flags} -o /dev/null -w '%{http_code}' --max-time 10 \
      "${alt}/api/v1/query?query=up" 2>/dev/null || echo "000")"
    if [[ "${alt_code}" == "200" ]]; then
      err "Prometheus is under ${alt} (got HTTP ${code} at ${base}/api/v1/query); using subpath."
      printf '%s\n' "${alt}"
      return 0
    fi
  fi

  die "Prometheus API not reachable at ${base}/api/v1/query (HTTP ${code}). If the UI redirects to /prometheus, set --url to http://host:port/prometheus"
}

prom_get() {
  local base="$1"
  local path="$2"
  local flags
  flags="$(curl_flags "${base}")"

  local body
  # Intentionally unquoted flags: expands to -s or -sk.
  # shellcheck disable=SC2086
  if ! body="$(curl ${flags} --fail --max-time 30 "${base}${path}")"; then
    die "Prometheus request failed: ${base}${path}"
  fi
  printf '%s\n' "${body}"
}

prom_query() {
  local base="$1"
  local query="$2"
  local flags
  flags="$(curl_flags "${base}")"
  local encoded
  encoded="$(printf '%s' "${query}" | jq -sRr @uri)"

  local body
  # shellcheck disable=SC2086
  if ! body="$(curl ${flags} --fail --max-time 30 \
    "${base}/api/v1/query?query=${encoded}")"; then
    die "Prometheus query failed"
  fi
  printf '%s\n' "${body}"
}

summarize_firing() {
  local raw="$1"
  local as_json="${2:-}"

  if [[ "${as_json}" == "json" ]]; then
    jq '[
      .data.result[]?
      | {
          alertname: (.metric.alertname // null),
          severity: (.metric.severity // .metric.channel // null),
          component: (.metric.component // null),
          alertstate: (.metric.alertstate // null),
          summary: null,
          description: null,
          startsAt: (if .value[0] then (.value[0] | todateiso8601) else null end),
          endsAt: null,
          labels: .metric,
          value: .value[1]
        }
    ]' <<<"${raw}"
    return
  fi

  jq -r '
    .data.result[]? |
    [
      (.metric.alertname // "-"),
      (.metric.severity // .metric.channel // "-"),
      (.metric.component // "-"),
      (.metric.alertstate // "-"),
      (.value[1] // "-")
    ] | @tsv
  ' <<<"${raw}" \
    | (printf 'ALERTNAME\tSEVERITY\tCOMPONENT\tSTATE\tVALUE\n'; cat) \
    | column -t -s $'\t' 2>/dev/null || cat
}

main() {
  local prom_url="${PROM_URL:-${PROM:-}}"
  local mode=""
  local query=""
  local as_json=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url)
        require_nonempty "${2:-}" "--url"
        prom_url="$2"
        shift 2
        ;;
      --firing|--rules)
        mode="$1"
        shift
        ;;
      --query)
        require_nonempty "${2:-}" "--query"
        mode="--query"
        query="$2"
        shift 2
        ;;
      --json)
        as_json="json"
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

  require_nonempty "${prom_url}" "Prometheus URL (--url, PROM_URL, or PROM)"
  require_nonempty "${mode}" "mode (--firing, --rules, --query)"
  prom_url="$(normalize_url "${prom_url}")"
  prom_url="$(resolve_prom_base "${prom_url}")"

  local raw
  case "${mode}" in
    --firing)
      raw="$(prom_query "${prom_url}" 'ALERTS{alertstate="firing"}')"
      local status
      status="$(jq -r '.status // "error"' <<<"${raw}")"
      [[ "${status}" == "success" ]] || die "Prometheus returned status=${status}: ${raw}"
      summarize_firing "${raw}" "${as_json}"
      ;;
    --rules)
      prom_get "${prom_url}" "/api/v1/rules" | jq .
      ;;
    --query)
      raw="$(prom_query "${prom_url}" "${query}")"
      jq . <<<"${raw}"
      ;;
    *)
      die "Unhandled mode: ${mode}"
      ;;
  esac
}

main "$@"
