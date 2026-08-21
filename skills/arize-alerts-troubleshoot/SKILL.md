---
name: arize-alerts-troubleshoot
description: >-
  Diagnoses self-hosted Arize AX clusters using read-only
  kubectl/Prometheus/Alertmanager access and local distribution docs. Use when
  troubleshooting self-hosted alerts, finding related documentation for firing
  alerts, or investigating self-hosted cluster health.
metadata:
  author: arize
  version: "1.0"
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

## Documentation link contract

For **every** section of documentation referenced, output:

```markdown
[<label>](file://<path-to-file>#<anchor>)
```

For example:

```markdown
[Reset Journal Heads procedure](file:///Users/me/onprem/release-11.43.0/docs/troubleshooting/gazette-troubleshooting.html#fix-reset-journal-heads)
```

Never type, reconstruct, or reformat these links yourself — paths get mistyped
and anchors get dropped. In the same turn as the answer, run `docs-search.py
--format markdown` for every cited section and paste its stdout unchanged. Do
not turn a path obtained elsewhere into a link. If you did not obtain a citation
from that command, do not include the local documentation link.

Before sending any answer containing documentation links, run:

```bash
python3 "$SKILL_ROOT/scripts/verify-doc-links.py" --file <draft>   # or pipe on stdin
```

It fails on a missing `file://` scheme, a path that does not exist, and a
missing or invented `#anchor`. Fix what it reports and re-run until it passes.

## Allowed commands (hard allowlist)

Run **only** these classes of operations unless the user explicitly overrides:

| Allowed | Examples |
|---|---|
| kubectl read | `safe-kubectl.sh -n <ns> get` / `describe` / `logs` / `top` |
| kubectl tunnel | `safe-kubectl.sh -n <ns> port-forward`, `safe-kubectl.sh proxy` |
| HTTP GET | Prometheus `/api/v1/*`, Alertmanager `/api/v2/*`, Kubernetes API via proxy |
| Local docs | Read/search files under `$ARIZE_DISTRIBUTION_ROOT/docs/` |
| Public docs | Fetch https://arize.com/docs/ax/selfhosting (and linked pages) |
| Skill scripts | Everything under `$SKILL_ROOT/scripts/` |

**All ad-hoc kubectl goes through** `$SKILL_ROOT/scripts/safe-kubectl.sh`
(allowlisted verbs, namespace required except cluster-scoped). Do not invoke
`kubectl` directly. Bundled scripts use the same wrapper for cluster reads and
tunnels. The only direct calls are the audited, read-only `kubectl config
current-context` / `config view --minify` checks in `preflight.sh`; `config` is
intentionally not exposed through the general wrapper because it also contains
mutating subcommands.

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
   `arize.sh`, `docs/`). Prefer exporting `ARIZE_DISTRIBUTION_ROOT` to that
   unpack root. Script flags `--distribution-root` / `--docs-root` may also
   point at the bare `docs/` folder (see `references/distribution.md`)
2. Set **`ARIZE_DISTRIBUTION_ROOT`** to that directory (or pass
   `--distribution-root`) — never guess among multiple release folders
3. `kubectl` context pointed at the cluster; `curl`, `jq`, `python3`, `tar`.
   Ad-hoc kubectl via `scripts/safe-kubectl.sh` only.
4. Namespace where Prometheus / Alertmanager run (ask if unknown)
5. Operator namespace for version check (often `arize-operator`; ask if unknown)

## Instructions

Copy this checklist and track progress:

```text
Progress:
- [ ] 1. Preflight (tools, distribution, kube context confirmation, version match)
- [ ] 2. Open read-only port-forwards (Prometheus, optional Alertmanager)
- [ ] 3. List firing Prometheus alerts
- [ ] 4. Join alerts to catalog + search local docs
- [ ] 5. Supplement with public self-hosting docs when local gaps remain
- [ ] 6. Summarize findings (no remediating writes)
```

### 1. Preflight (stop and ask if anything is missing)

Do **not** walk the filesystem for a distribution, and do **not** continue
until this step exits 0 **and** the user has confirmed the kube context.
Prompt the user with whatever `preflight.sh` prints after `ASK THE USER:`.

```bash
SKILL_ROOT="<path-to-this-skill>"   # directory containing SKILL.md
OPERATOR_NS="${OPERATOR_NS:-arize-operator}"

"$SKILL_ROOT/scripts/preflight.sh" \
  ${ARIZE_DISTRIBUTION_ROOT:+--distribution-root "$ARIZE_DISTRIBUTION_ROOT"} \
  --operator-namespace "$OPERATOR_NS"
```

`preflight.sh` prints `kube_context: <name>` (stdout and stderr). **Stop and
ask** whether that is the intended self-hosted cluster. Do not open
port-forwards, query Prometheus, or read cluster objects beyond preflight
until they confirm (or give a different context / `KUBE_CONTEXT`).

What it verifies (and what to ask when it fails):

| Check | Failure | Ask the user for |
|---|---|---|
| Tools (`kubectl`, `curl`, `jq`, `python3`, `tar`) | exit 1 | Install the missing tools |
| Distribution path (`ARIZE_DISTRIBUTION_ROOT`) | exit 1 | Unpack root (folder with `arize.sh` + `docs/`). Never guess among releases |
| Kube context | (always) | Confirm `kube_context` is the right cluster; switch and re-run if not |
| API server reachable from this shell | exit 5 | **Re-run with full network access first** — see below |
| ConfigMap `onprem-metadata` | exit 3 | Operator namespace (often `arize-operator`) and ConfigMap read permission |
| Distribution semver vs `last-applied-release` | exit 4 | The unpack that matches the cluster version |

**Exit 5 — your own shell is blocked, not the cluster.** If `kubectl` fails
with `Forbidden`, `no such host`, `i/o timeout`, or `dial tcp` while the
operator's terminal works, the agent shell is sandboxed or firewalled. Re-run
the skill's commands with unrestricted network access before saying anything
about VPN, cloud credentials, or the operator namespace. Never report this as a
cluster fault or a wrong namespace.

A failed cluster read is **not** a cluster-health finding — see
`references/access.md`. Version details: `references/distribution.md`.

Prefer `$ARIZE_DISTRIBUTION_ROOT/values.yaml` when that exact file exists. If
it is missing, read ConfigMap `arizeapp` in the operator namespace:

```bash
"$SKILL_ROOT/scripts/safe-kubectl.sh" -n "${OPERATOR_NS:-arize-operator}" \
  get configmap arizeapp -o yaml
```

Do not search the filesystem for alternate values files. If both sources are
unavailable, ask the user. Details: `references/distribution.md`.

### 2. Open ports (API-first)

```bash
# Typical application namespace — confirm if unknown
export ARIZE_NAMESPACE="<namespace>"
"$SKILL_ROOT/scripts/open-ports.sh" --namespace "$ARIZE_NAMESPACE"
# Prints PROM / AM export hints. Forwards run in their own session, so they
# survive this shell exiting; a port already serving is reused, not duplicated.
```

**If a `$PROM`/`$AM` query fails to connect, re-run the command above and retry
the query once.** Re-running is idempotent. A connection failure is an access
issue, never a cluster-health finding, so fix it and continue rather than
reporting it or narrating the tunnel bookkeeping.

Use `open-ports.sh` rather than backgrounding `port-forward` yourself — a bare
`&` tunnel is tied to this shell's process group and gets reaped between steps.
`--status` re-checks listeners; `--stop` tears them down.

The APIs live under `/prometheus` and `/alertmanager` (the bare host returns
302/404):

```bash
export PROM="http://localhost:9090/prometheus"
export AM="http://localhost:9093/alertmanager"
```

Optional kube API proxy (for API-style access):

```bash
"$SKILL_ROOT/scripts/safe-kubectl.sh" proxy --port=8080 &
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

# Citation lines for the sections being cited, ready to paste
python3 "$SKILL_ROOT/scripts/docs-search.py" \
  --list-sections docs/troubleshooting/gazette-troubleshooting.html \
  --section "reset journal heads" --format markdown
```

**Never hand-write a documentation link.** Take it from the `markdown` field.
The label may be shortened to fit a sentence; the URL in parentheses must be
copied byte for byte, per the documentation link contract above. A target
ending in `.html` means the anchor was lost — run `verify-doc-links.py` on the
draft to catch that before answering. See [citation rules](references/docs.md).

For each relevant hit, open and review the **complete section**, not only the
matching excerpt. Extract all remediation steps, verification checks,
prerequisites, and fallback/escalation conditions in their documented order.

Do not skip ahead. If the docs say to restart stalled consumers, verify
recovery, and perform de-sync recovery only if they remain stalled, recommend
the restart first unless the user confirms it was already tried. Present
de-sync recovery as the gated fallback, not the default recommendation. Never
execute either mutation.

Primary local assets for alert RCA (relative to `$ARIZE_DISTRIBUTION_ROOT`):

| Asset | Path |
|---|---|
| Alerts catalog (CSV) | `docs/troubleshooting/selfhosted-alerts-table.csv` |
| Troubleshooting guide | `docs/troubleshooting/troubleshooting-guide.html` |
| Alerts catalog intro | `docs/troubleshooting/selfhosted-alerts-catalog.html` |
| Gazette troubleshooting | `docs/troubleshooting/gazette-troubleshooting.html` |
| Architecture | `docs/architecture/core-components.html` |
| Operations / components | `docs/operations/operational-guide.html` |
| Grafana guide | `docs/operations/grafana-guide.html` |
| Values YAML parameters | `docs/reference/values-yaml-parameters.html` |
| Install values | `values.yaml` at distribution root; else ConfigMap `arizeapp` in the operator namespace |

Full docs inventory (architecture, install/platform, guides, advanced, ops,
reference, troubleshooting): `references/distribution.md`. Live list for this
unpack:

```bash
python3 "$SKILL_ROOT/scripts/docs-search.py" --list-docs
```

### 5. Public docs (when local is thin)

Start at the index, then fetch linked pages relevant to the alert/component:

- https://arize.com/docs/ax/selfhosting
- Full index: https://arize-ax.mintlify.site/docs/llms.txt

Prefer **local distribution docs** (version-matched to the install) over the
public site. Use public docs for install/ops concepts missing offline.

Cite the **specific relevant section** as a markdown link with the fragment in
the target — `https://` for public pages, `file://` for local distribution
files:

```markdown
[Self-hosting — Upgrade](https://arize.com/docs/ax/selfhosting/upgrade#prerequisites)
```

Anchors always come from `docs-search.py` — never invent or re-slug one. If none
is verified, link the page and name the exact heading. Full rules:
[documentation strategy](references/docs.md).

### 6. Summarize (read-only RCA)

For each high-severity alert (`page`, `page-biz-hours`, then `warning`):

1. Alertname, component, since when, severity
2. Catalog Description + Resolution (verbatim when present)
3. Full documented remediation procedure in order: first action,
   verification, fallback, and escalation gates
4. What the user has already tried and the earliest applicable next step; ask
   before skipping an unconfirmed earlier step
5. Local doc hits copied unchanged from `docs-search.py --format markdown`.
   Never independently construct an inline link from a known document path.
6. Section-anchored public doc links only if they add something the local tree
   lacks
7. Suggested **next diagnostic** (which pod to `safe-kubectl.sh … logs` /
   `describe`) — do not execute broad log pulls unless the user asks

Investigation discipline: see
[the investigation guide](references/investigation.md) and
[documentation strategy](references/docs.md).

## Examples

```bash
export ARIZE_DISTRIBUTION_ROOT="/path/to/arize-distribution"
export ARIZE_NAMESPACE="arize"
SKILL_ROOT="/path/to/arize-alerts-troubleshoot"
export PROM="http://localhost:9090/prometheus"

"$SKILL_ROOT/scripts/preflight.sh" --distribution-root "$ARIZE_DISTRIBUTION_ROOT"

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
