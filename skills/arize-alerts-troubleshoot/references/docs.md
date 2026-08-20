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
# Every verified heading anchor in one page
python3 "$SKILL_ROOT/scripts/docs-search.py" \
  --list-sections docs/troubleshooting/gazette-troubleshooting.html
```

Each hit carries `markdown` (**the paste-ready citation link**), plus the parts
it is built from: `doc_title`, `section`, `anchor` (the verified `id`),
`file_url`, `abs_path`, `open_command`, and `link` (relative, for naming a file
in prose). See [how to cite them](#cite-the-exact-section).

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

## Cite the exact section

A citation has to satisfy two things at once: it must be **clickable**, and it
must **carry the anchor**. Exactly one form does both — a normal markdown link
whose target is a `file://` URL. Paste `markdown` from `docs-search.py`
verbatim:

```markdown
- [Gazette Troubleshooting Guide — Fix: Reset Journal Heads](file:///Users/me/onprem/release-11.43.0/docs/troubleshooting/gazette-troubleshooting.html#fix-reset-journal-heads)
- [Values.yaml Parameters — Operator Parameters](file:///Users/me/onprem/release-11.43.0/docs/reference/values-yaml-parameters.html#operator-parameters)
```

The `file://` scheme is what keeps the fragment intact. A scheme-less path is
treated as a filename, so the client looks for a file literally ending in
`#fix-reset-journal-heads`, finds nothing, and the link dies; drop the fragment
to fix that and every section on a page collapses to the same link.

Never do any of the following:

- `` `file:///…#anchor` `` in backticks, or bare in text — correct target, but
  code spans and plain text are not clickable.
- `[label](/Users/…/gazette-troubleshooting.html#anchor)` — no scheme, so the
  anchor becomes part of the filename and nothing opens.
- `[label](/Users/…/gazette-troubleshooting.html)` — opens at the top of the
  page and silently loses the section.
- `[label](docs/troubleshooting/gazette-troubleshooting.html…)` — the relative
  `link` field. Use it to name a file in prose, never as a link target.
- `…/gazette-troubleshooting.html:4610` — a line number is not an anchor.
- `…#fix-restart-consumers` — anchors are copied, never pluralized,
  singularized, or retyped from heading text.

Rules:

- Paste `markdown` from `docs-search.py` or `--list-sections`. Both read the
  `id` out of the shipped page, so the section is known to exist. Never invent,
  guess, or re-slug an anchor.
- Name the section heading in the link label — `markdown` already does, as
  `Page — Section` — so the right part of the page is identifiable even if the
  link is copied as text.
- If a hit has `anchor: null`, no anchor was verified: link the page and name
  the exact heading in the text.
- Public docs work the same way, already being real URLs:
  `[label](https://…/page#section-id)`, fragment verified against that page.
- Offer `open_command` in a bash block **only** as a fallback, when a client
  refuses to follow `file://` links. It is a command to run, not a citation.

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
3. **Local docs** — the `markdown` citation link per section, each with a 2–4
   sentence excerpt
4. **Public docs** (optional) — anchored `https://…#section` link + why it adds
   value
5. **Next diagnostic** — single read-only `safe-kubectl.sh` / PromQL step (do
   not run a log firehose unless asked)
