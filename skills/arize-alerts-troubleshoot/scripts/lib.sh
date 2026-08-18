# lib.sh -- Shared helpers for arize-alerts-troubleshoot shell scripts.
#
# Source from sibling scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=lib.sh
#   source "${SCRIPT_DIR}/lib.sh"
#
# Provides: err, die, require_nonempty, normalize_url, curl_flags

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

normalize_url() {
  local url="$1"
  echo "${url%/}"
}

# -k (insecure TLS) only for localhost tunnels, or when explicitly opted in.
# Real ingress URLs must verify certificates unless --insecure / CURL_INSECURE=1.
curl_flags() {
  local url="$1"
  local insecure="${2:-0}"
  if [[ "${url}" != https://* ]]; then
    echo "-s"
    return
  fi
  if [[ "${insecure}" == "1" || "${CURL_INSECURE:-}" == "1" ]]; then
    echo "-sk"
    return
  fi
  local host="${url#https://}"
  host="${host%%/*}"
  if [[ "${host}" == \[* ]]; then
    host="${host#\[}"
    host="${host%%\]*}"
  else
    host="${host%%:*}"
  fi
  case "${host}" in
    localhost|127.0.0.1|::1)
      echo "-sk"
      ;;
    *)
      echo "-s"
      ;;
  esac
}
