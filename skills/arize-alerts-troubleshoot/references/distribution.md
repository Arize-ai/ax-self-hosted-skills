# Arize Distribution Root

This skill treats the **unpacked Arize distribution** as the source of truth
for product docs and the alerts catalog.

**Never guess the distribution path.** Operators often keep multiple release
directories and `values.yaml` files (different environments, upgrades in
progress, old tarballs). Walking the filesystem or picking the nearest folder
can attach the wrong docs/catalog to the wrong cluster.

## Distribution layout

After download + extract:

```text
arize-distribution/          # ← set ARIZE_DISTRIBUTION_ROOT here (explicitly)
  arize.sh                   # VERSION= is a git hash, not the numeric release
  arize-operator-chart.tgz   # Chart.yaml appVersion/version = numeric release (e.g. 11.43.0)
  docs/                      # offline HTML + CSV for this release
    index.html
    architecture/
    operations/
    troubleshooting/
      selfhosted-alerts-table.csv
      troubleshooting-guide.html
      ...
  examples/
  terraform/
  values.yaml                # may exist; do not assume it is the active install
```

The CSV and HTML under `docs/` are **version-matched** to that distribution
release. Prefer this tree over any older copy or the public website — but only
after the version check below passes.

## How the skill finds it

**Required:** an explicit path. Resolution order (first match wins):

1. **`--distribution-root <path>`** / **`--docs-root <path>`** (script flags)
2. **`$ARIZE_DISTRIBUTION_ROOT`**
3. **`$ARIZE_DIST`** (alias for `$ARIZE_DISTRIBUTION_ROOT`)

Do **not** walk upward from the working directory, the skill directory, or
search for `arize.sh` / `docs/` on disk. If neither a flag nor an env var is
set, **ask** which unpacked distribution directory to use (the folder that
contains `arize.sh` and `docs/`), then export it:

```bash
export ARIZE_DISTRIBUTION_ROOT="/path/to/unpacked/arize-distribution"
```

Verify the path is a distribution root:

```bash
test -f "$ARIZE_DISTRIBUTION_ROOT/arize.sh"
test -f "$ARIZE_DISTRIBUTION_ROOT/docs/troubleshooting/selfhosted-alerts-table.csv"
python3 "$SKILL_ROOT/scripts/catalog-lookup.py" --print-distribution-root
```

### Values files

Do not assume `$ARIZE_DISTRIBUTION_ROOT/values.yaml` is the file used by the
cluster. If investigation needs install settings, ask which `values.yaml` (or
equivalent) applies to this environment.

## Version check (required before using docs)

Docs and the alerts catalog must match the **release running in the cluster**.

`arize.sh` `VERSION` is a **git hash** (e.g. `d7c9c5a42`), not the numeric
release. The numeric version (e.g. `11.43.0`) is in the operator Helm chart
shipped with the distribution.

| Source | Field | Example |
|---|---|---|
| Distribution (semver) | `arize-operator-chart.tgz` → `Chart.yaml` `appVersion` (fallback: `version`) | `11.43.0` |
| Distribution (hash) | `arize.sh` → `VERSION=` | `d7c9c5a42` |
| Cluster (semver) | ConfigMap `onprem-metadata` → `last-applied-release` in the **operator** namespace (often `arize-operator`) | `11.43.0` |
| Cluster (hash) | same ConfigMap → `release-hash` | `d7c9c5a42` |

**Match on semver** (`appVersion` / `version` vs `last-applied-release`). The
hashes are useful cross-checks when present.

```bash
# Distribution semver (from Chart.yaml inside the operator chart tarball)
tar -xOf "$ARIZE_DISTRIBUTION_ROOT/arize-operator-chart.tgz" --wildcards '*/Chart.yaml' \
  | grep -E '^(appVersion|version):'

# Cluster semver
OPERATOR_NS="${OPERATOR_NS:-arize-operator}"
kubectl -n "$OPERATOR_NS" get configmap onprem-metadata \
  -o jsonpath='{.data.last-applied-release}{"\n"}'
```

Or:

```bash
"$SKILL_ROOT/scripts/check-version.sh" \
  --distribution-root "$ARIZE_DISTRIBUTION_ROOT" \
  --operator-namespace "$OPERATOR_NS"
```

**Rules:**

- Semver **matches** → proceed with local docs and catalog for this root.
- Semver **differs** → stop and ask for the distribution directory that matches
  `$CLUSTER_VERSION` (or confirm the operator namespace / ConfigMap if the
  cluster read looks wrong). Do not continue with mismatched docs.
- ConfigMap **missing** or key empty → say so; do not invent a version. Ask
  whether this is a fresh install or which release is expected.

Also useful for humans: Self-Hosted Dashboard → Help → About Self-Hosted shows
release info when the UI is up — still prefer the ConfigMap for the skill.

Do **not** use `upgradeNotesVersion` in `arize.sh` for this check — that field
is not available in most shipped distributions.

## What to read from the distribution

| Need | Open |
|---|---|
| What Arize is / core pieces | `docs/architecture/core-components.html` |
| Deployment options | `docs/architecture/platform-options.html` |
| Full component list + roles | `docs/operations/operational-guide.html` |
| Alert meanings + first fixes | `docs/troubleshooting/selfhosted-alerts-table.csv` |
| Deeper remediation | `docs/troubleshooting/troubleshooting-guide.html` |
| Gazette-specific | `docs/troubleshooting/gazette-troubleshooting.html` |
| Dashboards | `docs/operations/grafana-guide.html` |

Prefer the **CSV** for alert joins (`catalog-lookup.py`), then
`docs-search.py` / open matching HTML when Resolution needs more depth.

## Scratch output

```bash
export ARIZE_SKILL_TMP="${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}"
mkdir -p "$ARIZE_SKILL_TMP"
```
