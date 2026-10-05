---
name: arize-docs-validator
description: >-
  Validates Arize AX self-hosting documentation for broken images, broken
  internal and external links, text that promises a diagram with no image
  after it, and pages missing from the docs.json left nav. Use when checking
  docs before or after a publish, when a reader reports an image or link not
  working or a page that is hard to find, or when auditing a docs section.
metadata:
  author: arize
  version: "1.0"
compatibility: >-
  Requires python3 (standard library only) and HTTPS access to the docs site
  and any image hosts the docs reference.
---

# Arize Docs Validator Skill

Checks that docs render as expected: every image loads, every link resolves,
no page promises a diagram that is missing, and every page has a left-nav
entry.

## When to use

- Before merging a docs change: scan the Markdown source.
- After a publish, or when someone reports "an image is not showing": scan the
  live site.
- When asked to audit a section, for example everything under
  `/ax/selfhosting/`.

## Step 1: Pick a mode

| Mode | Input | Best for |
|---|---|---|
| `source` | A folder of `.md` / `.mdx` files | Catching problems before they ship. Resolves local image paths and internal links against files on disk, HTTP checks remote URLs, and flags pages missing from the nearest `docs.json` navigation. |
| `live` | A sitemap URL, such as `https://arize.com/docs/sitemap.xml`, plus an optional path prefix | Checking what readers actually see, including CDN and storage bucket issues. |

If the user does not say, use `source` when a docs folder is available,
otherwise `live` scoped to the section they mention.

## Step 2: Run the checker

```bash
python3 scripts/check-docs.py source <docs_dir> [--no-external]
python3 scripts/check-docs.py live https://arize.com/docs/sitemap.xml /ax/selfhosting/ [--no-external]
```

- `--no-external` skips third party links. Images are always checked.
- Exit code 1 means at least one error, so the script also works in CI.
- Run it where the network can reach the docs hosts. If every remote URL
  returns `ERR URLError` or `ERR ProxyError`, that is a network restriction on
  the machine running the script, not broken docs. Say so and stop instead of
  reporting every URL as broken.

## Step 3: Report

Lead with errors, then warnings. Group by page, and for each item give the
file and line (or page URL), what is broken, and the likely fix. End with a one
line summary of counts. Do not edit docs unless the user asks.

See [interpreting results](references/interpreting-results.md) for what each
finding usually means and how to fix it.

## Limits

- `live` mode parses server rendered HTML. Content that only appears after
  client side JavaScript runs can be missed. For those pages, check in a
  browser: an `<img>` whose `naturalWidth` is `0` after load failed.
- The navigation check only runs in `source` mode, and only when a Mintlify
  `docs.json` sits in the scanned folder or a folder above it. Point
  `source` at a folder inside the docs repo, such as `ax/selfhosting`. It
  skips `snippets/` folders and repo files such as `README.md`.
- The "diagram below" check is a heuristic. It looks six lines ahead for an
  image or Mermaid block and can flag intentional wording.
