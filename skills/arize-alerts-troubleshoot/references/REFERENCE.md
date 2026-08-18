# Self-Hosted Troubleshoot — Reference

## Layout

Skill + unpacked distribution:

```text
$ARIZE_DISTRIBUTION_ROOT/          # required knowledge root
  arize.sh
  arize-operator-chart.tgz
  values.yaml                      # default install values (ask if missing)
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
Install/config questions often need `values.yaml` plus
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

"$SKILL_ROOT/scripts/check-version.sh" \
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
kubectl proxy --port=8080
# Example read-only:
curl -s http://localhost:8080/api/v1/namespaces/<ns>/pods | jq '.items[].metadata.name'
```

Prefer `kubectl get/describe/logs` for routine checks; use the proxy when
API-style access is preferred.

## Scripts

| Script | Purpose |
|---|---|
| `open-ports.sh` | Background port-forwards for Prometheus / Alertmanager |
| `check-version.sh` | Compare chart `appVersion` to `onprem-metadata` `last-applied-release` |
| `prom-alerts.sh` | List firing alerts from Prometheus |
| `am-query.sh` | Query Alertmanager v2 API |
| `catalog-lookup.py` | Join alertname/component → distribution CSV |
| `docs-search.py` | Search local distribution docs for related text |

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
```

## Scratch output

```bash
export ARIZE_SKILL_TMP="${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}"
mkdir -p "$ARIZE_SKILL_TMP"
```
