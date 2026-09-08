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

Each hit carries `markdown` — the paste-ready citation link — plus `doc_title`,
`section`, `anchor` (the verified `id`), and `target`.

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
- For the full path inventory, see [the distribution guide](references/distribution.md)
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

**Never type a documentation link by hand.** Get it from `docs-search.py`, which
emits a ready `markdown` field. `--format markdown` makes stdout exactly the
lines to paste, and `--section` narrows to the sections being cited:

```bash
python3 "$SKILL_ROOT/scripts/docs-search.py" \
  --list-sections docs/troubleshooting/gazette-troubleshooting.html \
  --section "reset journal heads" --format markdown
```

```markdown
[Gazette Troubleshooting Guide — Fix: Reset Journal Heads](file:///Users/me/onprem/release-11.43.0/docs/troubleshooting/gazette-troubleshooting.html#fix-reset-journal-heads)
```

**The label may be reworded; the URL may not.** Shortening the label to fit a
sentence is fine — `[Reset Journal Heads](…#fix-reset-journal-heads)`. Copy the
text inside the parentheses byte for byte. Every local citation must start with
`file://` and end with `#<anchor>`; a target ending in `.html` means the anchor
was dropped and the link lands on the wrong part of the page.

Reconstructing a URL from memory, or from a file path seen earlier in the
investigation, is how paths get mistyped and anchors get dropped. Always re-run
the command above. Paste its stdout unchanged into the answer; do not build an
inline link from the document path.

```bash
python3 "$SKILL_ROOT/scripts/verify-doc-links.py" --file <draft>
```

It flags a missing `file://` scheme, a nonexistent path, and a missing or
invented anchor. Fix and re-run until it passes.

When the matched section has no `id`, `markdown` links the whole document
labeled with just the page title — the only case where a target has no `#`.

- Anchors come from the shipped page, so never invent, guess, or re-slug one.
- Local citations have one supported form: `file:///absolute/path#anchor`.
- Public docs work identically: `[label](https://…/page#section-id)`.

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
