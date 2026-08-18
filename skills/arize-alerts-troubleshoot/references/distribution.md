# Arize Distribution Root

This skill treats the **unpacked Arize distribution** as the source of truth
for product docs and the alerts catalog.

**Never guess the distribution path.** Operators often keep multiple release
directories (different environments, upgrades in progress, old tarballs).
Walking the filesystem or picking the nearest folder can attach the wrong
docs/catalog to the wrong cluster.

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
  values.yaml                # install values for this distribution root
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

### Values file

Treat **`$ARIZE_DISTRIBUTION_ROOT/values.yaml`** as the install values for this
cluster when that exact path exists.

```bash
test -f "$ARIZE_DISTRIBUTION_ROOT/values.yaml" && echo "values.yaml: ok"
```

If `values.yaml` is **not** present at the distribution root (missing, renamed,
or only available under another path), **ask** which values file to use before
relying on install settings (namespaces, ingress, sizing, feature flags, etc.).
Do not search the filesystem for alternate names or pick a nearby file.

## Version check (required before using docs)

Docs and the alerts catalog must match the **release running in the cluster**.

`arize.sh` `VERSION` is a **git hash** (e.g. `f3a8e21c7`), not the numeric
release. The numeric version (e.g. `11.43.0`) is in the operator Helm chart
shipped with the distribution.

| Source | Field | Example |
|---|---|---|
| Distribution (semver) | `arize-operator-chart.tgz` → `Chart.yaml` `appVersion` (fallback: `version`) | `11.43.0` |
| Distribution (hash) | `arize.sh` → `VERSION=` | `f3a8e21c7` |
| Cluster (semver) | ConfigMap `onprem-metadata` → `last-applied-release` in the **operator** namespace (often `arize-operator`) | `11.43.0` |
| Cluster (hash) | same ConfigMap → `release-hash` | `f3a8e21c7` |

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

Use `docs-search.py --list-docs` for the live inventory of this unpack (releases
can add pages). Typical shipped tree under `$ARIZE_DISTRIBUTION_ROOT/docs/`:

### Architecture
| Doc | Path |
|---|---|
| Core components | `docs/architecture/core-components.html` |
| Platform options | `docs/architecture/platform-options.html` |
| Disaster recovery / HA | `docs/architecture/resiliency.html` |

### Getting started
| Doc | Path |
|---|---|
| Overview | `docs/getting-started/overview.html` |
| Prerequisites | `docs/getting-started/prerequisites.html` |
| Deployment types | `docs/getting-started/deployment-types.html` |
| Download and unpack | `docs/getting-started/download-and-unpack-the-distribution.html` |
| Getting started FAQ | `docs/getting-started/faq.html` |

### Installation / platform
| Doc | Path |
|---|---|
| Installation index | `docs/installation/index.html` |
| Validate deployment | `docs/installation/validate-deployment.html` |
| Configuring SAML | `docs/installation/configuring-saml.html` |
| External Postgres | `docs/installation/external-postgres-requirements.html` |
| Configuring endpoints | `docs/installation/ingress/configuring-endpoints.html` |
| Other ingress controllers | `docs/installation/ingress/other-controllers.html` |
| Bare metal compatibility | `docs/installation/bare-metal-compatibility.html` |
| Single host | `docs/installation/installation-on-single-host.html` |
| GCP / Azure / AWS / IBM / OpenShift / Rancher guides | `docs/installation/<platform>/…` (quickstart, walkthrough, cluster, ingress) |

### Guides
| Doc | Path |
|---|---|
| Integrations | `docs/guides/integrations.html` |
| Multimodal blob offload | `docs/guides/multimodal-blob-offload.html` |
| SDK usage | `docs/guides/sdk-usage.html` |
| Python SDK v8 | `docs/on-premise-sdk-usage/version-8.html` |
| Python SDK v7 | `docs/on-premise-sdk-usage/version-7.html` |

### Operations / advanced / reference
| Doc | Path |
|---|---|
| Operational guide (component roles) | `docs/operations/operational-guide.html` |
| Grafana guide | `docs/operations/grafana-guide.html` |
| Helm | `docs/advanced/helm.html` |
| Fresh reinstall cleanup | `docs/advanced/fresh-reinstall-cleanup.html` |
| Values YAML parameters | `docs/reference/values-yaml-parameters.html` |

### Troubleshooting (start here for alerts)
| Doc | Path |
|---|---|
| Alerts catalog (CSV) | `docs/troubleshooting/selfhosted-alerts-table.csv` |
| Alerts catalog intro | `docs/troubleshooting/selfhosted-alerts-catalog.html` |
| Troubleshooting guide | `docs/troubleshooting/troubleshooting-guide.html` |
| Gazette troubleshooting | `docs/troubleshooting/gazette-troubleshooting.html` |
| Troubleshooting FAQ | `docs/troubleshooting/faq.html` |

### Other useful assets
| Asset | Path |
|---|---|
| Docs home | `docs/index.html` |
| Sizing CSVs (when present) | `docs/sizing_nonha.csv`, `docs/sizing_small1b.csv`, `docs/sizing_medium2b.csv` |

Prefer the **CSV** for alert joins (`catalog-lookup.py`), then
`docs-search.py` / open matching HTML when Resolution needs more depth. For
install settings, read `$ARIZE_DISTRIBUTION_ROOT/values.yaml` (see above) and
`docs/reference/values-yaml-parameters.html` for field meanings.

## Scratch output

```bash
export ARIZE_SKILL_TMP="${ARIZE_SKILL_TMP:-/tmp/arize-alerts-troubleshoot}"
mkdir -p "$ARIZE_SKILL_TMP"
```
