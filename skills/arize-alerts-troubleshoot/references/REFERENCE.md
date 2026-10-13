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
  scripts/check-secret-encoding.py # hubJwt/postgresPassword/cipherKey whitespace check
  scripts/prom-alerts.sh
  scripts/am-query.sh
  scripts/catalog-lookup.py
  scripts/docs-search.py
  scripts/verify-doc-links.py      # gate: documentation links resolve
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

Firing alerts (used by `prom-alerts.sh --firing`):

```
GET /api/v1/alerts
```

The script keeps alerts where `state == "firing"` and maps `activeAt` to
`startsAt` in `--json` output. Prefer this over instant-querying
`ALERTS{alertstate="firing"}` — that series does not carry the alert start
time.

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
when API-style access is preferred. The wrapper binds it to `127.0.0.1`,
rejects `POST`/`PUT`/`PATCH`/`DELETE`, and prevents callers from overriding
those filters.

## Scripts

| Script | Purpose |
|---|---|
| `lib.sh` | Shared shell helpers (`err`, `die`, `curl_flags`, …) sourced by the HTTP scripts |
| `distribution.py` | Shared distribution-root resolution used by the Python scripts |
| `safe-kubectl.sh` | Read-only kubectl wrapper; required for all ad-hoc kubectl |
| `preflight.sh` | Gate: tools, distribution root, kube context confirmation, API reachability, `onprem-metadata`, version match |
| `open-ports.sh` | Background port-forwards for Prometheus / Alertmanager |
| `check-version.sh` | Compare chart `appVersion` to `onprem-metadata` `last-applied-release` |
| `check-secret-encoding.py` | Detect whitespace corruption in hubJwt/postgresPassword/cipherKey and the hub-json-key pull secret |
| `prom-alerts.sh` | List firing alerts from Prometheus |
| `am-query.sh` | Query Alertmanager v2 API |
| `catalog-lookup.py` | Join alertname/component → distribution CSV |
| `docs-search.py` | Search local distribution docs for related text |
| `verify-doc-links.py` | Check a draft answer's documentation links resolve |

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
| 3 | Authentication/authorization/gateway access failure, or `onprem-metadata` unreadable |
| 4 | Distribution version does not match the cluster |
| 5 | This shell has no network path to the API server (agent sandbox / firewall) |

Exit 5 is a **tooling** failure: re-run with unrestricted network access before
reporting VPN, credential, namespace, or cluster-health problems.

### `check-secret-encoding.py`

```bash
python3 "$SKILL_ROOT/scripts/check-secret-encoding.py" \
  --distribution-root "$ARIZE_DISTRIBUTION_ROOT" \
  --operator-namespace "$OPERATOR_NS"
```

Checks `hubJwt`, `postgresPassword`, and `cipherKey` (`--field` to override
the list, repeatable) against every available source: local `values.yaml`
(if a distribution root is available), the cluster's consolidated
`arize-secrets` secret (`--secret-name` to override — each values.yaml field
name is also a Secret data key there), and for `hubJwt` only, the derived
`hub-json-key`-style `dockerconfigjson` pull secret (`--pull-secret-name`,
`--registry` to override the default `ch.hub.arize.com`) — that is the
credential actually presented to the registry and can drift from
`arize-secrets` if a pull secret wasn't regenerated after an update. Each
source is base64-decoded and checked for embedded/trailing whitespace — the
signature of `echo` (no `-n`) or a missing `tr -d '\n'` in the seeding
pipeline. Never prints the JWT, password, key, or any decoded credential
bytes — only whitespace byte offsets/counts and structural facts (segment
count, length).

Run this whenever a pod is `ImagePullBackOff`/`ErrImagePull` against the hub
registry and the kubelet event shows `401 Unauthorized` on the OAuth token
fetch. A JWT payload segment that still decodes as valid JSON with plausible
`iat`/`exp` claims is **not** evidence the credential is intact — that check
alone missed this exact bug once already, because a trailing-newline defect
in the encoded credential doesn't touch the payload segment. Only a
byte-level check on the fully decoded credential (what this script does)
catches it.

**`cipherKey` gets a lower-confidence check, and that distinction matters.**
`hubJwt` and `postgresPassword` are guaranteed printable text by their
documented generation methods, so any whitespace byte found is unambiguous
corruption. `cipherKey` may legitimately be raw random binary (the docs'
example is alphanumeric text, but say "adjust to your security process"),
and raw binary can contain a whitespace-range byte purely by chance. The
actual bug this script hunts for has one unmistakable signature regardless
of field — exactly one stray LF, as the very last byte — so that pattern is
always reported high-confidence; anything else found in a field listed in
`BINARY_CAPABLE_FIELDS` (currently just `cipherKey`) is reported
low-confidence instead. **Do not recommend re-seeding or rotating a
low-confidence `cipherKey` finding** — confirm with whoever generated it
whether it's raw binary first. Rotating a working `cipherKey` can make data
already encrypted under it unreadable.

Exit codes: `0` all checked sources clean, `1` high-confidence contamination
found, `2` usage, `3` no source could be checked (access problem, not a
finding), `4` only a low-confidence pattern found in a binary-capable field —
plausible false positive, confirm generation method before acting.

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
python3 "$SKILL_ROOT/scripts/docs-search.py" \
  --list-sections docs/troubleshooting/gazette-troubleshooting.html \
  --section verify --format markdown
```

`--format markdown` prints only citation lines, so stdout is exactly what gets
pasted. `--section TEXT` filters `--list-sections` by heading or anchor text.

Per-hit fields:

| Field | Meaning |
|---|---|
| `doc_title` | Page title, from `<h1>`/`<title>` |
| `section` | Heading text of the matched section (`null` if none verified) |
| `anchor` | Heading `id` read from the page (`null` if none verified) |
| `target` | `file:///…` document URL with `#anchor` appended, or the plain document |
| `markdown` | **Paste-ready citation:** `[Page — Section](target)`. Relabel freely; copy the URL exactly |
| `excerpt` | Surrounding text for the match |

Bare-path citations are not supported. Local citation targets always use a
`file:///absolute/path#anchor` URL.

Anchors are read from the shipped page, so a non-null `anchor` is guaranteed to
exist. Matches inside a page's nav/table of contents are ignored, and the chosen
section is the one whose heading matches the query or that contains the most
occurrences. `--list-sections` dumps every anchor in a page for precise citation.

Exit codes: `0` hits found, `2` no hits (or no sections for `--list-sections`).

### `verify-doc-links.py`

```bash
python3 "$SKILL_ROOT/scripts/verify-doc-links.py" --file draft.md
python3 "$SKILL_ROOT/scripts/verify-doc-links.py" --text "$ANSWER"
pbpaste | python3 "$SKILL_ROOT/scripts/verify-doc-links.py"
```

Checks every markdown link to a local doc: `file://` scheme present, file
exists, and `#anchor` present and real (anchors parsed by `docs-search.py`, so
both agree). `http(s)` links and anchorless formats such as CSV are skipped.

Exit codes: `0` all links resolve, `1` problems printed, `2` usage.

## Scratch output

```bash
export ARIZE_SKILL_TMP="${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}"
mkdir -p "$ARIZE_SKILL_TMP"
```
