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

1. Run `preflight.sh` (`distribution.md`): tools, explicit
   `$ARIZE_DISTRIBUTION_ROOT`, print kube context and **wait for the user to
   confirm it**, API server reachable, readable `onprem-metadata`, version
   match. Skim `architecture.md`. Prompt the user on any `ASK THE USER:` line.
   If it exits **5**, your shell has no network path to the API server: re-run
   with unrestricted network access before reporting anything about VPN,
   credentials, namespaces, or cluster health (`access.md`).
2. Open Prometheus (and optionally Alertmanager) via port-forward (`access.md`).
3. Pull firing alerts (`prom-alerts.sh --firing`).
4. Catalog join (`catalog-lookup.py`) using the CSV from the distribution.
5. Search local docs (`docs-search.py`); open matching troubleshooting HTML.
   Read the complete relevant section and extract its full ordered procedure,
   including checks and conditions between steps.
6. Classify:
   - `DeadMansSwitch` / heartbeat → expected firing; investigate only if
     *missing*.
   - Self-healing → note whether Kubernetes likely recovered; do not mutate.
   - Intervention required → present every relevant human remediation step in
     documented order, and identify the earliest applicable step (do not apply
     it yourself).
7. Confirm what the operator has already tried. Do not recommend step N+1
   unless step N was attempted, failed, or the docs explicitly say it does not
   apply.
8. Write RCA: alertname, since when, severity, doc evidence, full ordered
   remediation procedure, section-specific links, and next **read-only**
   diagnostic.

## Procedure completeness

Treat remediation as an ordered decision path, not a bag of possible fixes.
Review the entire relevant catalog Resolution and documentation section before
answering.

- Preserve prerequisites, intermediate verification, fallback, and escalation
  order.
- Lead with the least invasive documented step.
- Include later steps for completeness, clearly gated by failure or
  inapplicability of earlier steps.
- Ask what has already been attempted when that determines the next step.
- Never select a later, more invasive recovery merely because its paragraph
  contains a closer keyword match.

Example: for stalled consumers, if the docs say to restart consumers first,
verify recovery, and use de-sync recovery only if still stalled, present that
whole sequence and recommend the restart first unless it was already tried.

Cite docs so the reader reaches the right section in one click: paste the
`markdown` field from `docs-search.py`, a `[Page — Section](file://…#anchor)`
link. Do not put the URL in backticks or leave it bare — neither is clickable —
and do not drop the `file://` scheme, which is what preserves the anchor. Never
retype an anchor or use a `:<line>` suffix. See
[documentation strategy](docs.md).

## Root-cause bar

“Likely”, “probably”, “seems to” means you still have a hypothesis. Keep
digging or explicitly label the unresolved link and what query would prove it.

Prefer this chain when evidence exists:

1. Immediate failure (Prometheus `ALERTS` / Alertmanager)
2. State that made it possible (pod down, disk full, lag, missing dependency)
3. Event that produced that state (deploy, OOMKill, PVC full, upstream stall)

Start with (1) plus documentation. Deepen with targeted
`safe-kubectl.sh describe/logs` when the user asks.

## Context discipline

- Do **not** dump all pod logs into context.
- Prefer catalog + docs search hits over whole HTML files.
- Cap `docs-search.py` hits; summarize excerpts.
- When logs are needed: one component, recent window, error-filtered.
