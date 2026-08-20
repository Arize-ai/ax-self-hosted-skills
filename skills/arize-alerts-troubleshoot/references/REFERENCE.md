# Self-Hosted Troubleshoot — Reference

## Layout

Skill + unpacked distribution:

```text
$ARIZE_DISTRIBUTION_ROOT/          # required knowledge root
  arize.sh
  arize-operator-chart.tgz
  values.yaml                      # install values when present; else cm/arizeapp
  docs/
    index.html
    architecture/                  # core-components, platform-options, resiliency
    getting-started/               # overview, prerequisites, deployment types, FAQ, …
    installation/                  # platform install/ingress/validate/SAML/Postgres, …
    guides/                        # integrations, SDK, blob offload, …
    on-premise-sdk-usage/          # Python SDK v7 / v8
    operations/                    # operational-guide, grafana-guide
    advanced/                      # helm, fresh-reinstall-cleanup
    reference/                     # values-yaml-parameters
    troubleshooting/               # alerts CSV/catalog, troubleshooting-guide, gazette, FAQ
    sizing_*.csv                   # when present
  examples/
  terraform/

$SKILL_ROOT/                       # this skill (directory containing SKILL.md)
  SKILL.md
  references/
  scripts/lib.sh                   # shared shell helpers (err, curl_flags, …)
  scripts/distribution.py          # shared distribution-root resolution
  scripts/safe-kubectl.sh          # read-only kubectl wrapper (required for ad-hoc kubectl)
  scripts/preflight.sh             # tools + distribution + kube + version gate
  scripts/open-ports.sh
  scripts/check-version.sh
  scripts/prom-alerts.sh
  scripts/am-query.sh
  scripts/catalog-lookup.py
  scripts/docs-search.py
```
Full doc path table: `distribution.md`. Live inventory for this unpack:

```bash
python3 "$SKILL_ROOT/scripts/docs-search.py" --list-docs
```

When diagnosing, search the whole `docs/` tree (not only troubleshooting/).
Install/config questions often need `values.yaml` (or ConfigMap `arizeapp`
in the operator namespace — see `distribution.md`) plus
`docs/reference/values-yaml-parameters.html` and platform install guides under
`docs/installation/`.
## Diagnose loop

```bash
export ARIZE_DISTRIBUTION_ROOT="/path/to/arize-distribution"
export ARIZE_NAMESPACE="<namespace>"
OPERATOR_NS="${OPERATOR_NS:-arize-operator}"
SKILL_ROOT="/path/to/arize-alerts-troubleshoot"
OUT="${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}"
mkdir -p "$OUT"

"$SKILL_ROOT/scripts/preflight.sh" \
  --distribution-root "$ARIZE_DISTRIBUTION_ROOT" \
  --operator-namespace "$OPERATOR_NS"

"$SKILL_ROOT/scripts/open-ports.sh" --namespace "$ARIZE_NAMESPACE"
export PROM="${PROM:-http://localhost:9090/prometheus}"

"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --firing --json \
  | tee "$OUT/$(whoami)-$(date +%s)-prom-alerts.json" \
  | python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --stdin \
  > "$OUT/$(whoami)-$(date +%s)-alert-rca.json"

# For each high-severity alertname/component in the RCA JSON:
python3 "$SKILL_ROOT/scripts/docs-search.py" --query "<alertname>" --max-hits 20
```

Then open matching troubleshooting HTML from the search hits. Supplement with
https://arize.com/docs/ax/selfhosting only when local docs are insufficient.

## Prometheus HTTP API

Base URL = `--url` / `$PROM` / `$PROM_URL`.

```
GET /api/v1/query?query=...
GET /api/v1/query_range?query=...&start=...&end=...&step=...
GET /api/v1/rules
GET /api/v1/alerts
GET /api/v1/label/<name>/values
```

Firing alert series (used by `prom-alerts.sh`):

```
ALERTS{alertstate="firing"}
```

## Alertmanager HTTP API (v2)

Base URL = `--url` / `$AM` / `$AM_URL`.

```
GET /api/v2/alerts?active=true
GET /api/v2/alerts?filter={label=~"value"}
GET /api/v2/alerts/groups
GET /api/v2/silences
GET /api/v2/status
```

## Kubernetes API via kubectl proxy (optional)

```bash
"$SKILL_ROOT/scripts/safe-kubectl.sh" proxy --port=8080
# Example read-only:
curl -s http://localhost:8080/api/v1/namespaces/<ns>/pods | jq '.items[].metadata.name'
```

Prefer `safe-kubectl.sh get/describe/logs` for routine checks; use the proxy
when API-style access is preferred.

## Scripts

| Script | Purpose |
|---|---|
| `lib.sh` | Shared shell helpers (`err`, `die`, `curl_flags`, …) sourced by the HTTP scripts |
| `distribution.py` | Shared distribution-root resolution used by the Python scripts |
| `safe-kubectl.sh` | Read-only kubectl wrapper; required for all ad-hoc kubectl |
| `preflight.sh` | Gate: tools, distribution root, kube context confirmation, API reachability, `onprem-metadata`, version match |
| `open-ports.sh` | Background port-forwards for Prometheus / Alertmanager |
| `check-version.sh` | Compare chart `appVersion` to `onprem-metadata` `last-applied-release` |
| `prom-alerts.sh` | List firing alerts from Prometheus |
| `am-query.sh` | Query Alertmanager v2 API |
| `catalog-lookup.py` | Join alertname/component → distribution CSV |
| `docs-search.py` | Search local distribution docs for related text |

### `safe-kubectl.sh`

```bash
"$SKILL_ROOT/scripts/safe-kubectl.sh" -n "$ARIZE_NAMESPACE" get pods
"$SKILL_ROOT/scripts/safe-kubectl.sh" -n "$OPERATOR_NS" get configmap onprem-metadata
"$SKILL_ROOT/scripts/safe-kubectl.sh" -n "$ARIZE_NAMESPACE" logs deploy/<name> --tail=200
"$SKILL_ROOT/scripts/safe-kubectl.sh" -A get ns
```

### `preflight.sh`

```bash
"$SKILL_ROOT/scripts/preflight.sh" \
  --distribution-root "$ARIZE_DISTRIBUTION_ROOT" \
  --operator-namespace "$OPERATOR_NS"
```

| Exit | Meaning |
|---|---|
| 0 | All checks passed |
| 1 | Missing tools or distribution root — ask the user |
| 2 | Usage error |
| 3 | API server reachable but `onprem-metadata` unreadable (namespace / RBAC) |
| 4 | Distribution version does not match the cluster |
| 5 | This shell has no network path to the API server (agent sandbox / firewall) |

Exit 5 is a **tooling** failure: re-run with unrestricted network access before
reporting VPN, credential, namespace, or cluster-health problems.

### `prom-alerts.sh`

```bash
"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --firing
"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --firing --json
"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --rules
```

### `catalog-lookup.py`

```bash
python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --print-distribution-root
python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --alertname "up" --component "Historical"
python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --search "gazette"
"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --firing --json \
  | python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --stdin
```

Matching heuristics:

1. Exact match on CSV `Alert Name`
2. Reconstruct `"<alertname> (<component>)"`
3. Base alertname where the CSV parenthetical contains the component
4. Else `catalog_match: null` (still echo Prometheus fields)

### `docs-search.py`

```bash
python3 "$SKILL_ROOT/scripts/docs-search.py" --query "historical" --max-hits 20
python3 "$SKILL_ROOT/scripts/docs-search.py" --query "ALERTS" --path troubleshooting
python3 "$SKILL_ROOT/scripts/docs-search.py" --list-docs
python3 "$SKILL_ROOT/scripts/docs-search.py" \
  --list-sections docs/troubleshooting/gazette-troubleshooting.html
```

Per-hit fields:

| Field | Meaning |
|---|---|
| `path` | Doc path relative to the distribution root |
| `section` | Heading text of the matched section (`null` if none verified) |
| `anchor` | Heading `id` read from the page (`null` if none verified) |
| `link` | Relative `path#anchor` — for naming a file in prose |
| `abs_path` | Absolute page path, no fragment — **the markdown link target** |
| `file_url` | `file://…#anchor` — quote in backticks beside the link |
| `open_command` | `open`/`xdg-open` invocation that jumps to the section |
| `excerpt` | Surrounding text for the match |

A client that opens local files resolves the whole link target as a path, so an
anchored target (`…html#anchor`) does not open at all, while a bare page target
opens at the top. Link `abs_path` and deliver the anchor as `file_url` in
backticks. Public docs are ordinary URLs and take the fragment inline.

Anchors are read from the shipped page, so a non-null `anchor` is guaranteed to
exist. Matches inside a page's nav/table of contents are ignored, and the chosen
section is the one whose heading matches the query or that contains the most
occurrences. `--list-sections` dumps every anchor in a page for precise citation.

Exit codes: `0` hits found, `2` no hits (or no sections for `--list-sections`).

## Scratch output

```bash
export ARIZE_SKILL_TMP="${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}"
mkdir -p "$ARIZE_SKILL_TMP"
```
