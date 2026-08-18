"""Shared Arize distribution-root resolution for skill scripts.

Resolution order (first match wins):
  1. Explicit path (--distribution-root / --docs-root)
  2. $ARIZE_DISTRIBUTION_ROOT
  3. $ARIZE_DIST

A valid root contains both ``arize.sh`` and
``docs/troubleshooting/selfhosted-alerts-table.csv``.

Exception: an explicit flag may point at a bare ``docs/`` directory when the
alerts catalog CSV exists under ``docs/troubleshooting/``. In that case the
parent directory is returned as the distribution root. Env vars must still
point at the real unpack root (the folder with ``arize.sh``).
"""

from __future__ import annotations

import os
import pathlib

CATALOG_REL = pathlib.Path("docs/troubleshooting/selfhosted-alerts-table.csv")
MARKER_ARIZE_SH = "arize.sh"


def is_distribution_root(path: pathlib.Path) -> bool:
    return (path / CATALOG_REL).is_file() and (path / MARKER_ARIZE_SH).is_file()


def _coerce_explicit_root(root: pathlib.Path) -> pathlib.Path:
    """Accept a distribution root or its bare docs/ directory."""
    if is_distribution_root(root):
        return root

    # Allow --distribution-root / --docs-root pointing at docs/ when the
    # catalog CSV is present. Env vars must still be the real unpack root.
    docs_csv = root / "troubleshooting" / "selfhosted-alerts-table.csv"
    if root.name == "docs" and docs_csv.is_file():
        return root.parent

    raise SystemExit(
        f"Not a valid Arize distribution root (missing "
        f"{CATALOG_REL} and/or {MARKER_ARIZE_SH}): {root}\n"
        f"Pass the unpacked distribution directory (contains arize.sh and "
        f"docs/), or its docs/ folder when using --distribution-root / "
        f"--docs-root."
    )


def resolve_distribution_root(
    explicit: pathlib.Path | None = None,
    skill_dir: pathlib.Path | None = None,
) -> pathlib.Path:
    """Resolve unpacked arize-distribution root.

    Never walk the filesystem — operators often keep multiple releases.
    ``skill_dir`` is accepted for call-site compatibility but unused.
    """
    del skill_dir  # discovery by walk is forbidden

    if explicit is not None:
        return _coerce_explicit_root(explicit.expanduser().resolve())

    for env_name in ("ARIZE_DISTRIBUTION_ROOT", "ARIZE_DIST"):
        raw = os.environ.get(env_name, "").strip()
        if not raw:
            continue
        root = pathlib.Path(raw).expanduser().resolve()
        if not is_distribution_root(root):
            raise SystemExit(
                f"{env_name}={root} is not a valid Arize distribution root "
                f"(expected {CATALOG_REL} and {MARKER_ARIZE_SH})"
            )
        return root

    raise SystemExit(
        "Distribution root not set.\n"
        "Pass --distribution-root / --docs-root or export "
        "ARIZE_DISTRIBUTION_ROOT to the unpacked arize-distribution directory "
        "that matches this cluster (the folder that contains arize.sh and "
        "docs/). Do not guess among multiple release directories."
    )
