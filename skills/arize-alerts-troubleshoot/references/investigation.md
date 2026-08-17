# Investigation Discipline

## Scope rule

Explain **why this alert is firing**, not the cluster’s general health.

If you encounter other errors while investigating:

- **Include them** only if they clearly share the same incident (same
  component, same failure mode, same time window, or a direct
  upstream/downstream cause).
- **Ignore them** otherwise.

Ask: “Does this help explain why *this* alert fired?” If no, drop it.

## Workflow

1. Require an explicit `$ARIZE_DISTRIBUTION_ROOT` (`distribution.md`); run
   `check-version.sh` against `onprem-metadata` and skim `architecture.md`.
2. Open Prometheus (and optionally Alertmanager) via port-forward (`access.md`).
3. Pull firing alerts (`prom-alerts.sh --firing`).
4. Catalog join (`catalog-lookup.py`) using the CSV from the distribution.
5. Search local docs (`docs-search.py`); open matching troubleshooting HTML.
6. Classify:
   - `DeadMansSwitch` / heartbeat → expected firing; investigate only if
     *missing*.
   - Self-healing → note whether Kubernetes likely recovered; do not mutate.
   - Intervention required → surface catalog **Resolution** as the first
     human step (do not apply it yourself).
7. Write RCA: alertname, since when, severity, doc evidence, next **read-only**
   diagnostic.

## Root-cause bar

“Likely”, “probably”, “seems to” means you still have a hypothesis. Keep
digging or explicitly label the unresolved link and what query would prove it.

Prefer this chain when evidence exists:

1. Immediate failure (Prometheus `ALERTS` / Alertmanager)
2. State that made it possible (pod down, disk full, lag, missing dependency)
3. Event that produced that state (deploy, OOMKill, PVC full, upstream stall)

Start with (1) plus documentation. Deepen with targeted `kubectl describe/logs`
when the user asks.

## Context discipline

- Do **not** dump all pod logs into context.
- Prefer catalog + docs search hits over whole HTML files.
- Cap `docs-search.py` hits; summarize excerpts.
- When logs are needed: one component, recent window, error-filtered.
