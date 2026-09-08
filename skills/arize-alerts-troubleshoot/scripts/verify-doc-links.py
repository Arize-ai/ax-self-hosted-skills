#!/usr/bin/env python3
"""Check that documentation links in a draft answer actually resolve.

Every local citation must be `[label](file:///abs/path#anchor)`. This catches
the three ways a hand-written link goes wrong: a missing `file://` scheme, a
mistyped path, and a dropped or invented `#anchor`.

Run the draft answer through this before sending it:

    verify-doc-links.py --text "$ANSWER"
    pbpaste | verify-doc-links.py
    verify-doc-links.py --file draft.md

Exit codes:
    0  every documentation link resolves
    1  at least one link is broken (each problem is printed)
    2  usage
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import re
import sys
import urllib.parse

_MD_LINK_RE = re.compile(r"\[([^\]]*)\]\(\s*([^)\s]+)\s*\)")
_FENCE_RE = re.compile(r"^[ \t]*(`{3,}|~{3,})[ \t]*([^\s`]*)", re.MULTILINE)
_DOC_SUFFIXES = {".html", ".htm", ".md", ".csv", ".txt"}
_HTML_SUFFIXES = {".html", ".htm"}
_ANCHOR_SUFFIXES = {".html", ".htm", ".md"}


def _load_docs_search():
    """Import the sibling script so anchors are parsed the one same way."""
    path = pathlib.Path(__file__).resolve().parent / "docs-search.py"
    spec = importlib.util.spec_from_file_location("_docs_search", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(path.parent))
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.pop(0)
    return module


def _anchors_for(path: pathlib.Path, docs_search) -> set[str]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    sections = docs_search._collect_sections(raw, path.suffix.lower())
    return {anchor for _, anchor, _ in sections}


def _is_local_doc(target: str) -> bool:
    """A citation of a distribution doc, as opposed to a link between skill files.

    Citations are always absolute, so a bare sibling like `distribution.md` is
    left alone; a relative path into a docs tree is a malformed citation.
    """
    if target.startswith(("http://", "https://", "mailto:")):
        return False
    if "<" in target or ">" in target:
        return False  # placeholder such as file://<path>#<anchor>
    if target.startswith(("file://", "/")):
        return True
    # Relative links point at sibling skill docs; only a docs-tree page is a
    # citation that lost its scheme.
    path = pathlib.PurePosixPath(target.split("#")[0])
    return len(path.parts) > 1 and path.suffix in _HTML_SUFFIXES


def _split_fences(text: str) -> tuple[str, list[tuple[str, str]]]:
    """Return prose with fenced blocks removed, plus (language, body) per block."""
    prose_parts: list[str] = []
    blocks: list[tuple[str, str]] = []
    pos = 0

    while True:
        opening = _FENCE_RE.search(text, pos)
        if opening is None:
            break
        marker, language = opening.group(1), opening.group(2)
        body_start = text.find("\n", opening.end())
        if body_start == -1:
            break
        closing = re.compile(rf"^[ \t]*{marker[0]}{{{len(marker)},}}[ \t]*$", re.MULTILINE)
        end = closing.search(text, body_start)
        prose_parts.append(text[pos:opening.start()])
        blocks.append((language.lower(), text[body_start:end.start() if end else len(text)]))
        pos = end.end() if end else len(text)

    prose_parts.append(text[pos:])
    return "\n".join(prose_parts), blocks


def check_links(text: str, docs_search) -> list[str]:
    problems: list[str] = []
    prose, blocks = _split_fences(text)

    # A citation inside a code block renders as literal text, not a link. A
    # ```markdown block is an intentional example, so it is exempt.
    for language, body in blocks:
        if language == "markdown":
            continue
        for label, target in _MD_LINK_RE.findall(body):
            if target.startswith("file://"):
                problems.append(
                    f"[{label}] is inside a code block, so it is not clickable\n"
                    f"    move the citation into the prose of the answer"
                )

    for label, target in _MD_LINK_RE.findall(prose):
        if not _is_local_doc(target):
            continue

        raw_path, _, fragment = target.partition("#")

        if not target.startswith("file://"):
            problems.append(
                f"[{label}] missing file:// scheme -> {target}\n"
                f"    local citations must look like "
                f"[{label}](file:///abs/path.html#anchor)"
            )
            # Still check the rest so one run reports every problem.
            file_path = pathlib.Path(urllib.parse.unquote(raw_path))
        else:
            parsed = urllib.parse.urlparse(raw_path)
            file_path = pathlib.Path(urllib.parse.unquote(parsed.path))

        if not file_path.is_file():
            problems.append(
                f"[{label}] file does not exist -> {file_path}\n"
                f"    re-run docs-search.py instead of typing the path"
            )
            continue

        suffix = file_path.suffix.lower()
        if suffix not in _ANCHOR_SUFFIXES:
            continue  # CSV/TXT: whole-file links only

        anchors = _anchors_for(file_path, docs_search)

        if not fragment:
            if anchors:
                problems.append(
                    f"[{label}] no #anchor -> {target}\n"
                    f"    this lands at the top of the page; "
                    f"pick a section with: docs-search.py --list-sections "
                    f"{file_path} --format markdown"
                )
            continue

        if not anchors:
            problems.append(
                f"[{label}] could not parse anchors in {file_path}\n"
                f"    cannot verify #{fragment}; re-run docs-search.py --list-sections "
                f"{file_path} --format markdown"
            )
        elif fragment not in anchors:
            problems.append(
                f"[{label}] anchor #{fragment} is not in the page\n"
                f"    valid anchors come from: docs-search.py --list-sections "
                f"{file_path} --format markdown"
            )

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    src = parser.add_mutually_exclusive_group()
    src.add_argument("--text", help="Draft answer text to check")
    src.add_argument("--file", type=pathlib.Path, help="File containing the draft")
    args = parser.parse_args()

    if args.text is not None:
        text = args.text
    elif args.file is not None:
        if not args.file.is_file():
            raise SystemExit(f"Not a file: {args.file}")
        text = args.file.read_text(encoding="utf-8", errors="replace")
    else:
        text = sys.stdin.read()

    problems = check_links(text, _load_docs_search())
    if problems:
        print(f"{len(problems)} broken documentation link(s):\n")
        for problem in problems:
            print(f"  - {problem}")
        print("\nFix these before sending the answer.")
        return 1

    print("All documentation links resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
