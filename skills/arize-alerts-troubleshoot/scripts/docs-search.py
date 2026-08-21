#!/usr/bin/env python3
"""Search local Arize distribution docs for alert-related text.

Resolves the distribution root via scripts/distribution.py (same rules as
catalog-lookup.py).

Each hit reports the nearest verified heading anchor plus `markdown`: a
paste-ready `[Page — Section](/abs/path.html#anchor)` link. Sections without an
`id` fall back to a link to the whole document. Use --link-style file-url in a
terminal client, which linkifies only text carrying a URL scheme.

Usage:
    docs-search.py --query druidloader
    docs-search.py --query "single-shard-stall" --max-hits 15
    docs-search.py --query historical --path troubleshooting
    docs-search.py --list-docs
    docs-search.py --list-sections docs/troubleshooting/gazette-troubleshooting.html
"""

from __future__ import annotations

import argparse
import html
import json
import os
import pathlib
import re
import sys

from distribution import resolve_distribution_root

_DOC_GLOBS = ("**/*.html", "**/*.md", "**/*.csv", "**/*.txt")
_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")
_HTML_SUFFIXES = {".html", ".htm"}

# Heading anchors as authored in the shipped docs, e.g.
# <h2 id="fix-restart-consumer">Fix: Restart Consumer</h2>
_HEADING_RE = re.compile(
    r"<h([1-6])[^>]*\bid=[\"']([^\"']+)[\"'][^>]*>(.*?)</h\1>",
    re.IGNORECASE | re.DOTALL,
)
# Markdown headings with an explicit {#anchor}
_MD_ANCHOR_RE = re.compile(
    r"^(#{1,6})\s+(.*?)\s*\{#([^}]+)\}\s*$", re.MULTILINE
)
_MD_HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)
_TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
# Anchors mkdocs/material renders inside heading text; drop from titles.
_PERMALINK_RE = re.compile(r"¶|&para;|\ue157")


def _strip_html(text: str) -> str:
    text = _TAG_RE.sub(" ", text)
    text = html.unescape(text)
    return _WS_RE.sub(" ", text).strip()


def _slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9\s-]", "", text.lower())
    return re.sub(r"[\s-]+", "-", slug).strip("-")


def _heading_title(raw_inner: str) -> str:
    title = _strip_html(raw_inner)
    title = _PERMALINK_RE.sub("", title)
    # Headings sometimes end in ":"; it reads badly inside a link label
    return title.strip().rstrip(":").strip()


def _doc_title(raw: str, suffix: str, path: pathlib.Path) -> str:
    """Human-readable page title, for labeling a citation link."""
    if suffix in _HTML_SUFFIXES:
        m = _HEADING_RE.search(raw)
        if m and m.group(1) == "1":
            title = _heading_title(m.group(3))
            if title:
                return title
        m = _TITLE_RE.search(raw)
        if m:
            # mkdocs renders "<page> - <site name>"; keep the page part
            return _strip_html(m.group(1)).split(" - ")[0].strip()
    elif suffix == ".md":
        m = _MD_HEADING_RE.search(raw)
        if m:
            return m.group(2).strip()
    return path.stem.replace("-", " ").replace("_", " ").title()


def _collect_sections(raw: str, suffix: str) -> list[tuple[int, str, str]]:
    """Return [(offset, anchor, title)] sorted by offset.

    Only anchors that actually exist in the file are returned, so callers never
    invent a fragment. Markdown headings without an explicit {#id} fall back to
    the conventional GitHub-style slug.
    """
    sections: list[tuple[int, str, str]] = []

    if suffix in _HTML_SUFFIXES:
        for m in _HEADING_RE.finditer(raw):
            title = _heading_title(m.group(3))
            if title:
                sections.append((m.start(), m.group(2), title))
    elif suffix == ".md":
        explicit: set[int] = set()
        for m in _MD_ANCHOR_RE.finditer(raw):
            explicit.add(m.start())
            sections.append((m.start(), m.group(3), m.group(2).strip()))
        for m in _MD_HEADING_RE.finditer(raw):
            if m.start() in explicit:
                continue
            title = m.group(2).strip()
            slug = _slugify(title)
            if slug:
                sections.append((m.start(), slug, title))

    sections.sort(key=lambda s: s[0])
    return sections


def _section_for_offset(
    sections: list[tuple[int, str, str]], offset: int
) -> tuple[str, str] | None:
    """Nearest heading at or before offset."""
    found: tuple[str, str] | None = None
    for start, anchor, title in sections:
        if start <= offset:
            found = (anchor, title)
        else:
            break
    return found


def _searchable(raw: str, suffix: str) -> str:
    """Raw text with tags blanked so offsets still line up with the source."""
    if suffix not in _HTML_SUFFIXES:
        return raw
    return _TAG_RE.sub(lambda m: " " * len(m.group(0)), raw)


def _match_offsets(raw: str, suffix: str, query: str, limit: int = 200) -> list[int]:
    haystack = _searchable(raw, suffix).lower()
    needle = query.lower()
    if not needle:
        return []
    offsets: list[int] = []
    start = 0
    while len(offsets) < limit:
        idx = haystack.find(needle, start)
        if idx < 0:
            break
        offsets.append(idx)
        start = idx + len(needle)
    return offsets


def _best_section(
    raw: str, suffix: str, query: str
) -> tuple[str, str] | None:
    """Pick the verified anchor whose section actually covers the query.

    Occurrences inside a page's nav/table of contents sit before the first
    heading and are ignored, so a hit never anchors to the wrong place. A
    section whose own title matches wins; otherwise the section containing the
    most occurrences wins.
    """
    sections = _collect_sections(raw, suffix)
    if not sections:
        return None

    q = query.lower()
    body_start = sections[0][0]
    counts: dict[str, int] = {}
    titles: dict[str, str] = {}

    for offset in _match_offsets(raw, suffix, query):
        if offset < body_start:
            continue  # nav / TOC region
        match = _section_for_offset(sections, offset)
        if match is None:
            continue
        anchor, title = match
        counts[anchor] = counts.get(anchor, 0) + 1
        titles[anchor] = title

    if not counts:
        return None

    for anchor, title in titles.items():
        if q in title.lower():
            return anchor, title

    best = max(counts.items(), key=lambda kv: kv[1])[0]
    return best, titles[best]


def _md_escape(text: str) -> str:
    return text.replace("[", "\\[").replace("]", "\\]")


def _citation(
    path: pathlib.Path,
    anchor: str | None,
    section: str | None,
    doc_title: str,
    link_style: str = "path",
) -> dict:
    """Paste-ready citation for one doc section.

    `target` is the document with the verified anchor appended, and falls back
    to the plain document when the section has no `id`. `link_style` picks the
    form the client can open: `path` for clients that resolve local paths,
    `file-url` for terminals, which only linkify text carrying a URL scheme.
    """
    resolved = path.resolve()
    target = resolved.as_uri() if link_style == "file-url" else str(resolved)
    if anchor:
        target = f"{target}#{anchor}"
    label = f"{doc_title} — {section}" if section and anchor else doc_title
    return {
        "doc_title": doc_title,
        "section": section,
        "anchor": anchor,
        "target": target,
        "markdown": f"[{_md_escape(label)}]({target})",
    }


def _iter_doc_files(
    docs_root: pathlib.Path, path_filter: str | None
) -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    base = docs_root
    if path_filter:
        base = docs_root / path_filter
        if not base.exists():
            raise SystemExit(f"Path filter not found under docs/: {path_filter}")
    for pattern in _DOC_GLOBS:
        files.extend(p for p in base.glob(pattern) if p.is_file())
    # Stable, unique
    return sorted({p.resolve() for p in files})


def _excerpt(text: str, query: str, radius: int = 120) -> str | None:
    lower = text.lower()
    q = query.lower()
    idx = lower.find(q)
    if idx < 0:
        return None
    start = max(0, idx - radius)
    end = min(len(text), idx + len(query) + radius)
    snippet = text[start:end].strip()
    if start > 0:
        snippet = "…" + snippet
    if end < len(text):
        snippet = snippet + "…"
    return snippet


def search_docs(
    docs_root: pathlib.Path,
    query: str,
    *,
    path_filter: str | None,
    max_hits: int,
    max_bytes: int,
    link_style: str = "path",
) -> list[dict]:
    hits: list[dict] = []
    q = query.lower()
    for path in _iter_doc_files(docs_root, path_filter):
        try:
            raw = path.read_bytes()[:max_bytes].decode("utf-8", errors="replace")
        except OSError:
            continue
        suffix = path.suffix.lower()
        plain = _strip_html(raw) if suffix in _HTML_SUFFIXES else raw
        if q not in plain.lower() and q not in str(path).lower():
            continue
        try:
            rel_s = str(path.relative_to(docs_root.parent))
        except ValueError:
            rel_s = str(path)

        anchor: str | None = None
        section: str | None = None
        best = _best_section(raw, suffix, query)
        if best is not None:
            anchor, section = best

        hits.append(
            {
                "path": rel_s,
                **_citation(
                    path,
                    anchor,
                    section,
                    _doc_title(raw, suffix, path),
                    link_style,
                ),
                "excerpt": _excerpt(plain, query)
                or _excerpt(str(path), query)
                or plain[:200],
            }
        )
        if len(hits) >= max_hits:
            break
    return hits


def list_sections(
    path: pathlib.Path, docs_root: pathlib.Path, link_style: str = "path"
) -> dict:
    """Every verified anchor in one doc, for citing a section precisely."""
    if not path.is_file():
        raise SystemExit(f"Not a file: {path}")
    raw = path.read_text(encoding="utf-8", errors="replace")
    try:
        rel_s = str(path.relative_to(docs_root.parent))
    except ValueError:
        rel_s = str(path)
    suffix = path.suffix.lower()
    sections = _collect_sections(raw, suffix)
    doc_title = _doc_title(raw, suffix, path)
    return {
        "path": rel_s,
        "doc_title": doc_title,
        "section_count": len(sections),
        "sections": [
            _citation(path, a, t, doc_title, link_style) for _, a, t in sections
        ],
    }


def list_docs(docs_root: pathlib.Path, path_filter: str | None) -> list[str]:
    out = []
    for path in _iter_doc_files(docs_root, path_filter):
        try:
            out.append(str(path.relative_to(docs_root.parent)))
        except ValueError:
            out.append(str(path))
    return out


def main() -> int:
    skill_dir = pathlib.Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--distribution-root",
        "--docs-root",
        dest="distribution_root",
        type=pathlib.Path,
        help="Unpacked arize-distribution directory (or its docs/ folder)",
    )
    parser.add_argument("--query", help="Substring to search for (case-insensitive)")
    parser.add_argument(
        "--path",
        dest="path_filter",
        help="Limit to a subdirectory under docs/ (e.g. troubleshooting)",
    )
    parser.add_argument("--max-hits", type=int, default=20)
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=2_000_000,
        help="Max bytes to read per file",
    )
    parser.add_argument(
        "--list-docs",
        action="store_true",
        help="List doc files under the distribution and exit",
    )
    parser.add_argument(
        "--link-style",
        choices=("path", "file-url"),
        default=os.environ.get("ARIZE_DOCS_LINK_STYLE", "path"),
        help=(
            "Citation link form: 'path' for clients that open local paths "
            "(IDE chat); 'file-url' for terminals, which linkify only URLs. "
            "Defaults to $ARIZE_DOCS_LINK_STYLE or 'path'."
        ),
    )
    parser.add_argument(
        "--list-sections",
        metavar="DOC",
        help=(
            "List verified heading anchors for one doc "
            "(path relative to the distribution root, or absolute)"
        ),
    )
    args = parser.parse_args()

    root = resolve_distribution_root(args.distribution_root, skill_dir=skill_dir)
    docs_root = root / "docs"
    if not docs_root.is_dir():
        raise SystemExit(f"No docs/ directory under {root}")

    if args.list_docs:
        print(json.dumps({
            "distribution_root": str(root),
            "docs": list_docs(docs_root, args.path_filter),
        }, indent=2))
        return 0

    if args.list_sections:
        target = pathlib.Path(args.list_sections)
        if not target.is_absolute():
            target = root / target
        payload = list_sections(target.resolve(), docs_root, args.link_style)
        payload["distribution_root"] = str(root)
        print(json.dumps(payload, indent=2))
        return 0 if payload["section_count"] else 2

    if not args.query:
        parser.error("Provide --query, --list-docs, or --list-sections")

    hits = search_docs(
        docs_root,
        args.query,
        path_filter=args.path_filter,
        max_hits=args.max_hits,
        max_bytes=args.max_bytes,
        link_style=args.link_style,
    )
    print(json.dumps({
        "distribution_root": str(root),
        "query": args.query,
        "hit_count": len(hits),
        "hits": hits,
        "public_docs_index": "https://arize.com/docs/ax/selfhosting",
        "public_docs_llms_txt": "https://arize-ax.mintlify.site/docs/llms.txt",
    }, indent=2))
    return 0 if hits else 2


if __name__ == "__main__":
    sys.exit(main())
