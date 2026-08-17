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
- Prefer hits under `docs/troubleshooting/` and `docs/operations/`.
- Open the HTML file and quote the relevant section; do not dump entire files
  into context.

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

## Presenting doc results

For each alert, structure the answer as:

1. **Catalog** — Description, Severity, Self-Healing vs Intervention, Resolution
2. **Local docs** — file path + 2–4 sentence excerpt / section heading
3. **Public docs** (optional) — URL + why it adds value
4. **Next diagnostic** — single read-only kubectl/PromQL step (do not run a
   log firehose unless asked)
