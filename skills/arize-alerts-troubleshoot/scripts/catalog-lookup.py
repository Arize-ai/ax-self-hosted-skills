#!/usr/bin/env python3
"""Look up self-hosted alerts in the distribution selfhosted-alerts-table.csv.

Joins Prometheus/Alertmanager alertname/component fields to the alerts catalog
shipped inside an unpacked Arize distribution:

    $ARIZE_DISTRIBUTION_ROOT/docs/troubleshooting/selfhosted-alerts-table.csv

Usage:
    catalog-lookup.py --alertname up --component operator
    catalog-lookup.py --search druidloader
    catalog-lookup.py --print-distribution-root
    prom-alerts.sh --url "$PROM" --firing --json | catalog-lookup.py --stdin
"""

from __future__ import annotations

import argparse
import csv
import json
import pathlib
import re
import sys

from distribution import CATALOG_REL, resolve_distribution_root

_DISAMBIG_RE = re.compile(r"^(.*?)\s*\((.*)\)\s*$")


def resolve_catalog_path(
    csv_override: pathlib.Path | None,
    distribution_root: pathlib.Path | None,
    skill_dir: pathlib.Path | None,
) -> tuple[pathlib.Path, pathlib.Path | None]:
    """Return (catalog_csv, distribution_root_or_none)."""
    if csv_override is not None:
        path = csv_override.expanduser().resolve()
        if not path.is_file():
            raise SystemExit(f"Catalog not found: {path}")
        return path, distribution_root

    root = resolve_distribution_root(distribution_root, skill_dir=skill_dir)
    path = root / CATALOG_REL
    return path, root


def _load_catalog(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _parse_csv_name(alert_name: str) -> tuple[str, str | None]:
    m = _DISAMBIG_RE.match(alert_name.strip())
    if not m:
        return alert_name.strip(), None
    return m.group(1).strip(), m.group(2).strip()


def _score_row(
    row: dict[str, str], alertname: str, component: str | None
) -> int:
    """Higher score = better match. 0 means no match."""
    csv_name = (row.get("Alert Name") or "").strip()
    if not csv_name or not alertname:
        return 0

    base, disambig = _parse_csv_name(csv_name)
    alertname = alertname.strip()
    component = (component or "").strip() or None

    if csv_name == alertname:
        return 100
    if component and csv_name == f"{alertname} ({component})":
        return 95
    if base == alertname and component and disambig:
        tokens = [t.strip() for t in disambig.split(",")]
        if component == disambig or component in tokens:
            return 90
        if component.lower() in disambig.lower():
            return 70
    if base == alertname and not component:
        return 50
    if csv_name.lower() == alertname.lower():
        return 40
    return 0


def lookup(
    rows: list[dict[str, str]], alertname: str, component: str | None
) -> dict[str, str] | None:
    best: dict[str, str] | None = None
    best_score = 0
    for row in rows:
        score = _score_row(row, alertname, component)
        if score > best_score:
            best_score = score
            best = row
    return best if best_score > 0 else None


def search(rows: list[dict[str, str]], query: str) -> list[dict[str, str]]:
    q = query.lower()
    hits = []
    for row in rows:
        blob = " ".join(
            [
                row.get("Alert Name", ""),
                row.get("Description", ""),
                row.get("Resolution", ""),
            ]
        ).lower()
        if q in blob:
            hits.append(row)
    return hits


def _enrich(alert: dict, rows: list[dict[str, str]]) -> dict:
    alertname = alert.get("alertname") or ""
    component = alert.get("component")
    match = lookup(rows, alertname, component)
    out = dict(alert)
    if match is None:
        out["catalog_match"] = None
        return out
    out["catalog_match"] = {
        "alert_name": match.get("Alert Name"),
        "description": match.get("Description"),
        "severity": match.get("Severity"),
        "self_healing_or_intervention": match.get(
            "Self-Healing or Intervention"
        ),
        "resolution": match.get("Resolution"),
    }
    return out


def _row_payload(row: dict[str, str]) -> dict[str, str | None]:
    return {
        "alert_name": row.get("Alert Name"),
        "description": row.get("Description"),
        "severity": row.get("Severity"),
        "self_healing_or_intervention": row.get(
            "Self-Healing or Intervention"
        ),
        "resolution": row.get("Resolution"),
    }


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
    parser.add_argument(
        "--csv",
        type=pathlib.Path,
        help="Override path to selfhosted-alerts-table.csv",
    )
    parser.add_argument(
        "--print-distribution-root",
        action="store_true",
        help="Print resolved distribution root and exit",
    )
    parser.add_argument("--alertname", help="Alertmanager labels.alertname")
    parser.add_argument("--component", help="Alertmanager labels.component")
    parser.add_argument("--search", help="Substring search across catalog rows")
    parser.add_argument(
        "--stdin",
        action="store_true",
        help="Read JSON array of {alertname, component, ...} from stdin",
    )
    args = parser.parse_args()

    if args.print_distribution_root:
        root = resolve_distribution_root(
            args.distribution_root, skill_dir=skill_dir
        )
        print(root)
        return 0

    catalog_path, dist_root = resolve_catalog_path(
        args.csv, args.distribution_root, skill_dir=skill_dir
    )
    rows = _load_catalog(catalog_path)

    if args.stdin:
        raw = sys.stdin.read()
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            print(f"Invalid JSON on stdin: {exc}", file=sys.stderr)
            return 1
        if isinstance(payload, dict):
            payload = [payload]
        if not isinstance(payload, list):
            print("stdin JSON must be an object or array", file=sys.stderr)
            return 1
        for i, alert in enumerate(payload):
            if not isinstance(alert, dict):
                print(
                    f"stdin JSON element {i} must be an object, got {type(alert).__name__}",
                    file=sys.stderr,
                )
                return 1
        result = {
            "distribution_root": str(dist_root) if dist_root else None,
            "catalog": str(catalog_path),
            "alerts": [_enrich(a, rows) for a in payload],
        }
        print(json.dumps(result, indent=2))
        return 0

    if args.search:
        hits = search(rows, args.search)
        print(json.dumps([_row_payload(r) for r in hits], indent=2))
        return 0

    if not args.alertname:
        parser.error(
            "Provide --alertname, --search, --stdin, or "
            "--print-distribution-root"
        )

    match = lookup(rows, args.alertname, args.component)
    if match is None:
        print(json.dumps({
            "alertname": args.alertname,
            "component": args.component,
            "catalog": str(catalog_path),
            "catalog_match": None,
        }, indent=2))
        return 2

    print(json.dumps(_row_payload(match), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
