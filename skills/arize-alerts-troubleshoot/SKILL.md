---
name: arize-alerts-troubleshoot
description: >-
  Diagnoses self-hosted Arize AX clusters using read-only
  kubectl/Prometheus/Alertmanager access and local distribution docs. Use when
  troubleshooting self-hosted alerts, finding related documentation for firing
  alerts, or investigating self-hosted cluster health.
---

# Self-Hosted Troubleshoot

Diagnose firing alerts on a self-hosted Arize AX cluster. Requires:

1. `kubectl` access to the Arize cluster
2. An unpacked **Arize distribution** (or a path to its `docs/` folder)
3. HTTP reachability to Prometheus / Alertmanager (ingress or port-forward)

**Workflow:** pull currently firing Prometheus alerts → join them to the shipped
alerts catalog → gather related documentation from the local distribution and,
when useful, the public self-hosting docs at
https://arize.com/docs/ax/selfhosting.

## Allowed commands (hard allowlist)

Run **only** these classes of operations unless the user explicitly overrides:

| Allowed | Examples |
|---|---|
| kubectl read | `get`, `describe`, `logs`, `top`, `api-resources`, `version` |
| kubectl tunnel | `port-forward`, `proxy` (to open local HTTP endpoints) |
| HTTP GET | Prometheus `/api/v1/*`, Alertmanager `/api/v2/*`, Kubernetes API via proxy |
| Local docs | Read/search files under `$ARIZE_DISTRIBUTION_ROOT/docs/` |
| Public docs | Fetch https://arize.com/docs/ax/selfhosting (and linked pages) |
| Skill scripts | Everything under `$SKILL_ROOT/scripts/` |

**Forbidden:** `apply`, `create`, `delete`, `patch`, `edit`, `scale`, `exec`,
`rollout restart`, `cordon`, `drain`, `taint`, mutating HTTP APIs, shelling
into pods, or writing to cluster objects.

Prefer **HTTP APIs** (curl/Python against local port-forwards) over inventing
long bash pipelines.

## When to Use

- A self-hosted alert is firing (PagerDuty / Slack / email / UI)
- Clarifying what an alert means and which docs apply
- First-pass RCA before deeper log diving
- Mapping cluster symptoms to distribution troubleshooting guides

## Prerequisites

1. Unpacked Arize distribution that matches the cluster release (contains
   `arize.sh`, `docs/`)
2. Set **`ARIZE_DISTRIBUTION_ROOT`** to that directory (or pass
   `--distribution-root`) — never guess among multiple release folders
3. `kubectl` context pointed at the cluster; `curl`, `jq`, `python3`
4. Namespace where Prometheus / Alertmanager run (ask if unknown)
5. Operator namespace for version check (often `arize-operator`; ask if unknown)

## Instructions

Copy this checklist and track progress:

```text
Progress:
- [ ] 1. Set distribution root explicitly + verify version vs cluster
- [ ] 2. Open read-only port-forwards (Prometheus, optional Alertmanager)
- [ ] 3. List firing Prometheus alerts
- [ ] 4. Join alerts to catalog + search local docs
- [ ] 5. Supplement with public self-hosting docs when local gaps remain
- [ ] 6. Summarize findings (no remediating writes)
```

### 1. Resolve the distribution (explicit + version check)

Ask for the unpacked distribution path if `$ARIZE_DISTRIBUTION_ROOT` is unset.
Do **not** walk the filesystem to find one.

```bash
export ARIZE_DISTRIBUTION_ROOT="/path/to/unpacked/arize-distribution"
SKILL_ROOT="<path-to-this-skill>"   # directory containing SKILL.md
OPERATOR_NS="${OPERATOR_NS:-arize-operator}"

python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --print-distribution-root
"$SKILL_ROOT/scripts/check-version.sh" \
  --distribution-root "$ARIZE_DISTRIBUTION_ROOT" \
  --operator-namespace "$OPERATOR_NS"
```

See `references/distribution.md`. Interpret the result by exit code:

| Exit | Meaning | Next step |
|---|---|---|
| 0 | Versions match | Proceed |
| 1 | Real mismatch | Ask for the distribution matching `last-applied-release`; do not use these docs |
| 3 | Cluster unreadable (kubectl error, missing ConfigMap, empty field) | Fix cluster access first — see `references/access.md`. Do not report a version mismatch or a cluster fault |

A failed `kubectl` read says nothing about cluster health. Never turn one into a
finding. Do not assume `$ARIZE_DISTRIBUTION_ROOT/values.yaml` is the active
install file.
### 2. Open ports (API-first)

```bash
# Typical application namespace — confirm if unknown
export ARIZE_NAMESPACE="<namespace>"
"$SKILL_ROOT/scripts/open-ports.sh" --namespace "$ARIZE_NAMESPACE"
# Prints PROM / AM export hints; leaves port-forwards running in background
```

Or manually (see `references/access.md`):

```bash
kubectl -n "$ARIZE_NAMESPACE" port-forward svc/prometheus 9090:9090 &
kubectl -n "$ARIZE_NAMESPACE" port-forward svc/alertmanager 9093:9093 &
# APIs are under /prometheus and /alertmanager (bare host returns 302/404)
export PROM="http://localhost:9090/prometheus"
export AM="http://localhost:9093/alertmanager"
```

Optional kube API proxy (for API-style access):

```bash
kubectl proxy --port=8080 &
export KUBE_PROXY="http://localhost:8080"
```

### 3. Pull firing alerts

Prefer Prometheus (source of truth for rule evaluation):

```bash
OUT="${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}"
mkdir -p "$OUT"

"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --firing --json \
  > "$OUT/$(whoami)-$(date +%s)-prom-alerts.json"
```

Alertmanager is useful for routing/silence context:

```bash
"$SKILL_ROOT/scripts/am-query.sh" --url "$AM" --firing --json \
  > "$OUT/$(whoami)-$(date +%s)-am-alerts.json"
```

### 4. Join catalog + search local docs

```bash
# Enrich with shipped CSV (meanings, severity, first Resolution)
"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --firing --json \
  | python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --stdin \
  > "$OUT/$(whoami)-$(date +%s)-alert-rca.json"

# Find related HTML/Markdown under the distribution docs tree
python3 "$SKILL_ROOT/scripts/docs-search.py" \
  --query "<alertname or component>" \
  --max-hits 20
```

Primary local assets (relative to `$ARIZE_DISTRIBUTION_ROOT`):

| Asset | Path |
|---|---|
| Alerts catalog (CSV) | `docs/troubleshooting/selfhosted-alerts-table.csv` |
| Troubleshooting guide | `docs/troubleshooting/troubleshooting-guide.html` |
| Alerts catalog intro | `docs/troubleshooting/selfhosted-alerts-catalog.html` |
| Gazette troubleshooting | `docs/troubleshooting/gazette-troubleshooting.html` |
| Architecture | `docs/architecture/core-components.html` |
| Operations / components | `docs/operations/operational-guide.html` |
| Grafana guide | `docs/operations/grafana-guide.html` |

### 5. Public docs (when local is thin)

Start at the index, then fetch linked pages relevant to the alert/component:

- https://arize.com/docs/ax/selfhosting
- Full index: https://arize-ax.mintlify.site/docs/llms.txt

Prefer **local distribution docs** (version-matched to the install) over the
public site. Use public docs for install/ops concepts missing offline.

### 6. Summarize (read-only RCA)

For each high-severity alert (`page`, `page-biz-hours`, then `warning`):

1. Alertname, component, since when, severity
2. Catalog Description + Resolution (verbatim when present)
3. Local doc hits (paths + short excerpt)
4. Public doc links only if they add something the local tree lacks
5. Suggested **next diagnostic** (which pod to `logs`/`describe`) — do not
   execute broad log pulls unless the user asks

Investigation discipline: `references/investigation.md`.

## Examples

```bash
export ARIZE_DISTRIBUTION_ROOT="/path/to/arize-distribution"
export ARIZE_NAMESPACE="arize"
SKILL_ROOT="/path/to/arize-alerts-troubleshoot"
export PROM="http://localhost:9090/prometheus"

# What is firing?
"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --firing

# Join firing alerts to the catalog
"$SKILL_ROOT/scripts/prom-alerts.sh" --url "$PROM" --firing --json \
  | python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --stdin

# Docs for one alert / component
python3 "$SKILL_ROOT/scripts/docs-search.py" --query "druidloader" --max-hits 15
python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --alertname "up" --component "Historical"
```

## References

- `references/REFERENCE.md` — APIs, scripts, diagnose loop
- `references/access.md` — port-forward / proxy / namespace tips
- `references/distribution.md` — finding the docs root
- `references/docs.md` — local vs public documentation strategy
- `references/architecture.md` — component orientation
- `references/investigation.md` — scope and RCA bar
