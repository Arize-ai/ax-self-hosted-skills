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

Each hit carries `section` (heading text), `anchor` (the verified `id` from the
page), `abs_path` (the page, no fragment), `file_url` (`file://…#anchor`),
`open_command`, and `link` (relative, for naming a file in prose). See
[how to cite them](#cite-the-exact-section) — the anchor cannot go inside a
local-file link target.

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

Local distribution docs are files on disk, and a chat client that opens local
files resolves the **entire markdown link target as a filesystem path**. It does
not parse a fragment. So `…/gazette-troubleshooting.html#fix-restart-consumer`
as a link target is read as a request for a file whose name ends in
`#fix-restart-consumer`, which does not exist, and the link silently fails to
open. Dropping the fragment makes it open but lands at the top of the page.

Local files therefore cannot carry a section anchor inside a markdown link.
**The link target opens the page; the anchor is delivered beside it.** Use both
fields from `docs-search.py` — `abs_path` as the link target, and `file_url` in
backticks so the client renders it literally instead of rewriting it:

```markdown
- **Fix: Restart Consumer** — [open page](/Users/me/onprem/release-11.43.0/docs/troubleshooting/gazette-troubleshooting.html),
  jump to section: `file:///Users/me/onprem/release-11.43.0/docs/troubleshooting/gazette-troubleshooting.html#fix-restart-consumer`
```

Always name the section heading in the text, so the anchor is not the only way
to find the right part of the page. When several sections come from one page,
list the page once and the sections under it. To open a section directly, offer
the `open_command` value in a bash block:

```bash
open "file:///Users/me/onprem/release-11.43.0/docs/troubleshooting/gazette-troubleshooting.html#fix-restart-consumer"
```

Never do any of the following:

- `[Fix: Restart Consumer](/Users/…/gazette-troubleshooting.html#fix-restart-consumer)`
  — anchor inside a local link target. Will not open at all.
- `[Fix: Restart Consumer](/Users/…/gazette-troubleshooting.html)` — opens, but
  silently drops the section, so three different sections become the same link.
  The anchor must appear beside it.
- `[…](docs/troubleshooting/gazette-troubleshooting.html)` — the relative `link`
  field. Use it to name a file in prose, never as a link target.
- `…/gazette-troubleshooting.html:4610` — a line number is not an anchor.
- `…#fix-restart-consumers` — anchors are copied, never pluralized,
  singularized, or retyped from heading text.

Rules:

- Take `abs_path`, `file_url`, and `open_command` from `docs-search.py` or
  `--list-sections`. Both read the `id` out of the shipped page, so the section
  is known to exist. Never invent, guess, or re-slug an anchor.
- If a hit has `anchor: null`, no anchor was verified: link the page and name
  the exact heading in the text.
- **Public docs are different** — they are real URLs, so the fragment goes
  directly in the link target: `[label](https://…/page#section-id)`, verified
  against that page's headings.
- Label every citation with the page title plus the section heading, so the
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
3. **Local docs** — page link (`abs_path`) plus the section heading and its
   `file_url` in backticks, and a 2–4 sentence excerpt
4. **Public docs** (optional) — anchored `https://…#section` link + why it adds
   value
5. **Next diagnostic** — single read-only `safe-kubectl.sh` / PromQL step (do
   not run a log firehose unless asked)
