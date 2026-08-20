# Documentation strategy

## Authority order

| Priority | Source | Use for |
|---|---|---|
| 1 | Distribution CSV via `catalog-lookup.py` | Alert meaning, severity, self-healing, first Resolution |
| 2 | Local distribution HTML under `docs/` | Deeper remediation, component roles, ops guides |
| 3 | Public self-hosting docs | Concepts missing offline; install/ops explainers |
| 4 | Model prior knowledge | Last resort — never contradict the catalog |

Local docs are **version-matched** to the install. Public docs may lag or lead
a given release — say so when you rely on them.

## Local search

```bash
python3 "$SKILL_ROOT/scripts/docs-search.py" --query "<alertname or component>"
python3 "$SKILL_ROOT/scripts/docs-search.py" --list-docs
```

Search tips:

- Start with `alertname`, then `component`, then a symptom keyword from the
  catalog Description.
- Prefer hits under `docs/troubleshooting/` and `docs/operations/` for alert RCA.
- Also search `docs/architecture/`, `docs/installation/`, `docs/advanced/`,
  `docs/reference/`, and `docs/guides/` when the symptom is install, Helm,
  values, ingress, Postgres, or SDK related.
- Open the HTML file and quote the relevant section; do not dump entire files
  into context.
- Read the complete relevant section, including numbered steps, prerequisites,
  warnings, and fallback/escalation steps. Do not stop at the first matching
  keyword or quote only the most invasive step.
- For the full path inventory, see [the distribution guide](distribution.md)
  or `--list-docs`.

## Public docs

Entry points:

- https://arize.com/docs/ax/selfhosting
- Machine-readable index: https://arize-ax.mintlify.site/docs/llms.txt

When to fetch public pages:

- Local tree has no hit for the alert/component
- The question is about install / platform setup (not alert RCA)
- You need a stable URL to cite in the summary

When **not** to:

- Catalog already has a clear Resolution
- Local troubleshooting guide covers the same ground

## Link to the exact section

When giving the user a web documentation link, link to the most specific
section available, not merely the page root:

- Prefer the page's canonical heading URL with its fragment, such as
  `https://example/page#recovery-steps`.
- If the public page has a table of contents or heading anchors, verify the
  fragment targets the section you actually used.
- If no stable section anchor exists, link the page and name the exact heading
  beside it (for example, “Recovery steps”).
- For local distribution HTML, report the relative file path and exact heading.
  If that HTML exposes a stable `id`, include it as `path.html#section-id`.
- Never invent an anchor from heading text without verifying it exists.

## Preserve the documented remediation order

Before recommending any action, read the **full ordered procedure** in the
catalog Resolution and matching documentation section. Extract every relevant
step in order, including conditions that permit moving to the next step.

For example, if stalled-consumer guidance says:

1. restart the affected consumers;
2. verify whether consumption resumes; then
3. perform de-sync recovery only if the restart did not resolve the stall;

present all three in that order. Do not jump directly to de-sync recovery.

Rules:

- Distinguish **first action**, **verification**, **fallback**, and
  **last-resort/escalation** steps.
- Recommend the earliest not-yet-tried applicable step.
- Mention later steps for completeness, but label their prerequisites
  explicitly (“only if step 1 fails…”).
- If the user has not said whether an earlier step was attempted, ask before
  recommending the later step.
- These remediation actions are for a human operator. The skill remains
  read-only and must not execute restarts, recovery, or other mutations.

## Presenting doc results

For each alert, structure the answer as:

1. **Catalog** — Description, Severity, Self-Healing vs Intervention, Resolution
2. **Full ordered procedure** — every relevant documented step, its gate, and
   which step is next based on what the user has already tried
3. **Local docs** — file path + exact section heading (and verified anchor,
   when present) + 2–4 sentence excerpt
4. **Public docs** (optional) — section-specific URL + why it adds value
5. **Next diagnostic** — single read-only `safe-kubectl.sh` / PromQL step (do
   not run a log firehose unless asked)
