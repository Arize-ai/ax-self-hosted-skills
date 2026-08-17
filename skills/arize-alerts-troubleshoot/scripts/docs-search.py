#!/usr/bin/env python3
"""Search local Arize distribution docs for alert-related text.

Resolves the distribution root the same way as catalog-lookup.py.

Usage:
    docs-search.py --query druidloader
    docs-search.py --query "single-shard-stall" --max-hits 15
    docs-search.py --query historical --path troubleshooting
    docs-search.py --list-docs
"""

from __future__ import annotations

import argparse
import html
import json
import os
import pathlib
import re
import sys

_CATALOG_REL = pathlib.Path("docs/troubleshooting/selfhosted-alerts-table.csv")
_MARKER_ARIZE_SH = "arize.sh"
_DOC_GLOBS = ("**/*.html", "**/*.md", "**/*.csv", "**/*.txt")
_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


def _is_distribution_root(path: pathlib.Path) -> bool:
    return (path / _CATALOG_REL).is_file() and (path / _MARKER_ARIZE_SH).is_file()


def resolve_distribution_root(
    explicit: pathlib.Path | None = None,
    skill_dir: pathlib.Path | None = None,
) -> pathlib.Path:
    """Resolve unpacked arize-distribution root.

    Order: explicit flag → ARIZE_DISTRIBUTION_ROOT → ARIZE_DIST.
    Never walk the filesystem — operators often keep multiple releases.
    """
    del skill_dir  # kept for call-site compatibility; discovery by walk is forbidden

    if explicit is not None:
        root = explicit.expanduser().resolve()
        if not _is_distribution_root(root):
            # Allow a bare docs/ parent if CSV exists under troubleshooting/
            docs_csv = root / "troubleshooting" / "selfhosted-alerts-table.csv"
            if root.name == "docs" and docs_csv.is_file():
                return root.parent
            raise SystemExit(
                f"Not a valid Arize distribution root (missing "
                f"{_CATALOG_REL} and/or {_MARKER_ARIZE_SH}): {root}"
            )
        return root

    for env_name in ("ARIZE_DISTRIBUTION_ROOT", "ARIZE_DIST"):
        raw = os.environ.get(env_name, "").strip()
        if not raw:
            continue
        root = pathlib.Path(raw).expanduser().resolve()
        if not _is_distribution_root(root):
            raise SystemExit(
                f"{env_name}={root} is not a valid Arize distribution root"
            )
        return root

    raise SystemExit(
        "Distribution root not set.\n"
        "Pass --distribution-root / --docs-root or export "
        "ARIZE_DISTRIBUTION_ROOT to the unpacked arize-distribution directory "
        "that matches this cluster (the folder that contains arize.sh and "
        "docs/). Do not guess among multiple release directories."
    )


def _strip_html(text: str) -> str:
    text = _TAG_RE.sub(" ", text)
    text = html.unescape(text)
    return _WS_RE.sub(" ", text).strip()


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
) -> list[dict]:
    hits: list[dict] = []
    q = query.lower()
    for path in _iter_doc_files(docs_root, path_filter):
        try:
            raw = path.read_bytes()[:max_bytes].decode("utf-8", errors="replace")
        except OSError:
            continue
        plain = _strip_html(raw) if path.suffix.lower() in {".html", ".htm"} else raw
        if q not in plain.lower() and q not in str(path).lower():
            continue
        try:
            rel_s = str(path.relative_to(docs_root.parent))
        except ValueError:
            rel_s = str(path)
        hits.append(
            {
                "path": rel_s,
                "excerpt": _excerpt(plain, query)
                or _excerpt(str(path), query)
                or plain[:200],
            }
        )
        if len(hits) >= max_hits:
            break
    return hits


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
        help="Unpacked arize-distribution directory (or its docs/ parent)",
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

    if not args.query:
        parser.error("Provide --query or --list-docs")

    hits = search_docs(
        docs_root,
        args.query,
        path_filter=args.path_filter,
        max_hits=args.max_hits,
        max_bytes=args.max_bytes,
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
