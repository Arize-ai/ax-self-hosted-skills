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

Each hit carries `section` (the heading text), `anchor` (the verified `id` from
the page), `link` (relative `path#anchor`, for naming a file in prose), and
`file_url` — the clickable `file://…#anchor` URI. **Cite `file_url` verbatim.**

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

A documentation citation must be a link that **actually opens**. Two things are
required: a URL scheme, and the anchor inside the link target.

Local distribution docs are files on disk, so they need a `file://` URI. A bare
absolute path like `/Users/…/gazette-troubleshooting.html#etcd-alert` has no
scheme, so nothing can resolve it and clicking does nothing. The `file://` form
also opens the page in a browser, which is what makes the fragment jump to the
section — the same file opened in an editor ignores anchors entirely.

Copy `file_url` from `docs-search.py` exactly as returned:

```markdown
[Gazette troubleshooting — Fix: Restart Consumer](file:///Users/me/onprem/release-11.43.0/docs/troubleshooting/gazette-troubleshooting.html#fix-restart-consumer)
[Values.yaml Parameters — Required Parameters](file:///Users/me/onprem/release-11.43.0/docs/reference/values-yaml-parameters.html#required-parameters)
```

Never do any of the following, all of which produce a link that does not open:

- `/Users/…/gazette-troubleshooting.html#etcd-alert` — absolute path with no
  `file://` scheme. Correct anchor, dead link.
- `docs/troubleshooting/gazette-troubleshooting.html#etcd-alert` — the relative
  `link` field. Use it to name a file in prose, not as a link target.
- `…/gazette-troubleshooting.html:4610` — a line number is not an anchor, and
  `:<line>` breaks the target.
- `…/gazette-troubleshooting.html), fragment #etcd-alert` — the fragment belongs
  in the URL, not narrated next to it.
- `…/gazette-troubleshooting.html#fix-restart-consumers` — anchors are copied,
  never pluralized, singularized, or retyped from heading text.

Rules:

- Take the whole target from `file_url`, or build it from `--list-sections`.
  Both read the `id` out of the shipped page, so the section is known to exist.
- Never invent, guess, or re-slug an anchor from heading text.
- If a hit has `anchor: null`, no anchor was verified: link the page `file_url`
  and name the exact heading in the text beside it.
- Public docs need a scheme too, and follow the same shape:
  `https://…/page#section-id`, fragment verified against that page's headings.
- Label every link with the page title plus the section heading, so the
  destination is clear before clicking.

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
3. **Local docs** — a clickable `file://…#anchor` link labeled with page and
   section heading, plus a 2–4 sentence excerpt
4. **Public docs** (optional) — anchored `https://` section URL + why it adds
   value
5. **Next diagnostic** — single read-only `safe-kubectl.sh` / PromQL step (do
   not run a log firehose unless asked)
