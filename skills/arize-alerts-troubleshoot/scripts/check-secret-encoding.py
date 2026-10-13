#!/usr/bin/env python3
"""check-secret-encoding.py -- Detect base64 encoding corruption in
values.yaml secrets shared with the Arize central hub / cluster.

Several values.yaml fields are documented as "store base64-encoded" via the
same seeding pipeline: ``echo -n '<value>' | base64 | tr -d '\\n'`` --
notably ``hubJwt`` (license JWT), ``postgresPassword``, and ``cipherKey``
(see "Seed hubJwt" / "Set postgresPassword and cipherKey" in the detailed
install walkthrough for your cloud). Dropping ``-n`` on ``echo``, or skipping
the trailing ``tr -d '\\n'`` on the base64 output, embeds a stray newline (or
other whitespace) inside the decoded secret. The corrupted value still looks
fine under casual inspection -- it is valid base64, and (for hubJwt) the JWT
payload segment still parses as JSON with plausible-looking claims -- so it
is easy to misdiagnose a resulting auth failure as a licensing or credential
problem instead of an encoding bug.

This script never prints any secret, JWT, password, or key material, nor any
decoded bytes. It reports only: which fields were checked, whether whitespace
contamination was found, which control character it was, and its byte
offset.

Sources checked per field (whichever are available):
  1. Local values.yaml (--distribution-root / $ARIZE_DISTRIBUTION_ROOT)
  2. The cluster's consolidated secret (default: arize-secrets) in the
     operator namespace, where each values.yaml field name is also a
     Secret data key
  3. hubJwt only: the derived image-pull secret (default: hub-json-key),
     since that is the credential actually presented to the registry and
     can drift from arize-secrets/values.yaml if a pull secret was not
     regenerated after an update

Usage:
  check-secret-encoding.py [--distribution-root <path>]
                            [--operator-namespace <ns>]
                            [--secret-name <name>]
                            [--pull-secret-name <name>]
                            [--registry <host>]
                            [--field <name> ...]
                            [--context <ctx>]

Not every field can be judged the same way. ``hubJwt`` and
``postgresPassword`` are guaranteed pure printable text by their documented
generation methods (a JWT; a password drawn from ``tr -dc 'a-zA-Z0-9'``), so
*any* whitespace byte in either is unambiguous corruption. ``cipherKey`` is
different: some teams generate it as raw random binary rather than the
doc's alphanumeric-source example, and raw binary can contain a
whitespace-range byte (e.g. 0x0B) purely by chance -- a false positive that
looks identical to real corruption unless you also look at *where* it is.
The actual bug this script hunts for (``echo`` instead of ``echo -n``, or a
skipped trailing ``tr -d '\\n'``) has one unmistakable signature regardless of
field: exactly one stray LF, and it is the very last byte. Anything else
found in a binary-capable field (currently: cipherKey) is reported as
low-confidence and must NOT be treated as confirmed corruption, and the
value must NOT be rotated/re-seeded on the strength of this check alone --
ask whoever generated it whether it is raw binary before acting. Rotating a
working cipherKey can make data already encrypted under it unreadable.

Exit codes:
  0  all available sources for all fields are clean (no whitespace contamination)
  1  high-confidence contamination found (safe to recommend re-seeding)
  2  usage / invalid args
  3  no source could be checked for any field -- not a finding, fix access and retry
  4  only a low-confidence pattern found, in a binary-capable field (e.g.
     cipherKey) -- plausible false positive from genuine random binary;
     confirm the generation method before treating this as a finding
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import os
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import distribution  # noqa: E402

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
SAFE_KUBECTL = SCRIPT_DIR / "safe-kubectl.sh"

DEFAULT_FIELDS = ["hubJwt", "postgresPassword", "cipherKey"]

# Fields whose documented generation method permits raw binary, so a
# whitespace-range byte can occur by chance rather than by encoding bug.
BINARY_CAPABLE_FIELDS = {"cipherKey"}

WHITESPACE_NAMES = {
    0x09: "TAB",
    0x0A: "LF",
    0x0D: "CR",
    0x0B: "VT",
    0x0C: "FF",
    0x20: "SPACE",
}

# clean: no whitespace found.
# high: unambiguous corruption -- any hit in a guaranteed-text field, or the
#   exact "echo without -n" signature (single trailing LF) in any field.
# low: a binary-capable field has whitespace bytes but not that signature --
#   plausible in genuine random binary; do not act on this alone.
CONFIDENCE_CLEAN = "clean"
CONFIDENCE_HIGH = "high"
CONFIDENCE_LOW = "low"


def classify(field: str, hits: list[tuple[int, str]], length: int) -> str:
    if not hits:
        return CONFIDENCE_CLEAN

    is_classic_signature = (
        len(hits) == 1 and hits[0][1] == "LF" and hits[0][0] == length - 1
    )
    if is_classic_signature:
        return CONFIDENCE_HIGH

    if field in BINARY_CAPABLE_FIELDS:
        return CONFIDENCE_LOW

    return CONFIDENCE_HIGH


def err(msg: str) -> None:
    print(msg, file=sys.stderr)


def find_whitespace(data: bytes) -> list[tuple[int, str]]:
    """Return (offset, name) for every whitespace/control byte found."""
    return [(i, WHITESPACE_NAMES[b]) for i, b in enumerate(data) if b in WHITESPACE_NAMES]


def decode_b64_relaxed(raw: str) -> bytes:
    return base64.b64decode(raw, validate=False)


def report_source(label: str, field: str, decoded: bytes, check_jwt_shape: bool) -> str:
    """Print a pass/fail report for one decoded credential. Returns a
    CONFIDENCE_* constant."""
    hits = find_whitespace(decoded)
    confidence = classify(field, hits, len(decoded))

    print(f"source: {label}")
    print(f"  length: {len(decoded)} bytes")
    if check_jwt_shape:
        looks_like_jwt = len(decoded.split(b".")) == 3
        print(f"  looks_like_jwt (3 dot-separated segments): {looks_like_jwt}")

    if confidence == CONFIDENCE_CLEAN:
        print("  whitespace_contamination: none")
        return confidence

    print(f"  whitespace_contamination: {len(hits)} byte(s) found")
    for offset, name in hits[:10]:
        at_end = offset >= len(decoded) - 2
        loc = "near end" if at_end else "embedded"
        print(f"    - {name} at byte offset {offset}/{len(decoded)} ({loc})")
    if len(hits) > 10:
        print(f"    ... and {len(hits) - 10} more")

    if confidence == CONFIDENCE_HIGH:
        print(
            "  likely cause: seeding pipeline used `echo` instead of "
            "`echo -n`, or skipped `tr -d '\\n'` on the base64 output, "
            "embedding a newline or space inside the encoded value."
        )
    else:
        print(
            "  confidence: LOW -- this field may legitimately be raw random "
            "binary (not guaranteed text), which can contain a "
            "whitespace-range byte by chance. This does NOT match the "
            "exact 'echo without -n' signature (single trailing LF). Do not "
            "treat this as confirmed corruption or rotate the value without "
            "first confirming the generation method with whoever set it."
        )
    return confidence


def read_values_yaml_field(root: pathlib.Path, field: str) -> bytes | None:
    values_path = root / "values.yaml"
    if not values_path.is_file():
        err(f"local check skipped: no values.yaml at {values_path}")
        return None

    prefix = f"{field}:"
    raw_value = None
    for line in values_path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix):
            raw_value = stripped[len(prefix):].strip().strip('"').strip("'")
            break

    if not raw_value:
        err(f"local check skipped: no {field} key found in {values_path}")
        return None

    try:
        return decode_b64_relaxed(raw_value)
    except binascii.Error as e:
        err(f"local {field} in {values_path} is not valid base64: {e}")
        return None


def kubectl_get(args: list[str], context: str | None) -> subprocess.CompletedProcess:
    cmd = [str(SAFE_KUBECTL)]
    if context:
        cmd += ["--context", context]
    cmd += args
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30)


def read_cluster_secret_field(
    namespace: str, secret_name: str, field: str, context: str | None
) -> bytes | None:
    try:
        proc = kubectl_get(
            ["-n", namespace, "get", "secret", secret_name, "-o", f"jsonpath={{.data.{field}}}"],
            context,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        err(f"cluster check skipped: could not run safe-kubectl.sh: {e}")
        return None

    if proc.returncode != 0:
        err(
            f"cluster check skipped: could not read secret/{secret_name} "
            f"field {field} in namespace {namespace}: {proc.stderr.strip()}"
        )
        return None

    raw = proc.stdout.strip()
    if not raw:
        err(f"cluster check skipped: secret/{secret_name} has no data.{field}")
        return None

    try:
        return decode_b64_relaxed(raw)
    except binascii.Error as e:
        err(f"cluster check skipped: data.{field} is not valid base64: {e}")
        return None


def read_pull_secret_password(
    namespace: str, secret_name: str, registry: str, context: str | None
) -> bytes | None:
    try:
        proc = kubectl_get(
            [
                "-n",
                namespace,
                "get",
                "secret",
                secret_name,
                "-o",
                r"jsonpath={.data.\.dockerconfigjson}",
            ],
            context,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        err(f"pull-secret check skipped: could not run safe-kubectl.sh: {e}")
        return None

    if proc.returncode != 0:
        err(
            f"pull-secret check skipped: could not read secret/{secret_name} "
            f"in namespace {namespace}: {proc.stderr.strip()}"
        )
        return None

    raw = proc.stdout.strip()
    if not raw:
        err(f"pull-secret check skipped: secret/{secret_name} has no .dockerconfigjson data")
        return None

    try:
        dockerconfig = json.loads(decode_b64_relaxed(raw))
    except (binascii.Error, json.JSONDecodeError) as e:
        err(f"pull-secret check skipped: could not decode .dockerconfigjson: {e}")
        return None

    creds = dockerconfig.get("auths", {}).get(registry)
    if creds is None:
        err(f"pull-secret check skipped: no auths entry for registry '{registry}'")
        return None

    auth_b64 = creds.get("auth", "")
    if not auth_b64:
        err(f"pull-secret check skipped: auths['{registry}'].auth is empty")
        return None

    try:
        decoded = decode_b64_relaxed(auth_b64)
    except binascii.Error as e:
        err(f"pull-secret check skipped: auth field is not valid base64: {e}")
        return None

    if b":" not in decoded:
        err("pull-secret check skipped: decoded auth has no ':' separator")
        return None
    _, _, password = decoded.partition(b":")
    return password


def check_field(
    field: str,
    root: pathlib.Path | None,
    operator_ns: str,
    secret_name: str,
    pull_secret_name: str,
    registry: str,
    context: str | None,
) -> tuple[bool, set[str]]:
    """Returns (checked_any, confidences_seen) for this field."""
    checked_any = False
    confidences: set[str] = set()
    is_jwt_field = field == "hubJwt"

    def record(label: str, decoded: bytes) -> None:
        nonlocal checked_any
        checked_any = True
        confidences.add(report_source(label, field, decoded, is_jwt_field))

    if root is not None:
        decoded = read_values_yaml_field(root, field)
        if decoded is not None:
            record(f"values.yaml {field} ({root / 'values.yaml'})", decoded)

    cluster_decoded = read_cluster_secret_field(operator_ns, secret_name, field, context)
    if cluster_decoded is not None:
        record(f"cluster secret {operator_ns}/{secret_name} data.{field}", cluster_decoded)

    if is_jwt_field:
        pull_decoded = read_pull_secret_password(operator_ns, pull_secret_name, registry, context)
        if pull_decoded is not None:
            record(
                f"pull secret {operator_ns}/{pull_secret_name} "
                f"(auths['{registry}'].auth password)",
                pull_decoded,
            )

    return checked_any, confidences


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--distribution-root", "--docs-root", dest="distribution_root")
    parser.add_argument(
        "--operator-namespace",
        default=os.environ.get("OPERATOR_NS", "arize-operator"),
    )
    parser.add_argument(
        "--secret-name",
        default="arize-secrets",
        help="Consolidated cluster secret holding values.yaml fields (default: arize-secrets)",
    )
    parser.add_argument(
        "--pull-secret-name",
        default="hub-json-key",
        help="Derived image-pull secret, checked for hubJwt only (default: hub-json-key)",
    )
    parser.add_argument("--registry", default="ch.hub.arize.com")
    parser.add_argument(
        "--field",
        dest="fields",
        action="append",
        help=f"values.yaml field to check; repeatable (default: {', '.join(DEFAULT_FIELDS)})",
    )
    parser.add_argument("--context")
    args = parser.parse_args()

    fields = args.fields or DEFAULT_FIELDS

    explicit_root = pathlib.Path(args.distribution_root) if args.distribution_root else None
    root = None
    try:
        root = distribution.resolve_distribution_root(explicit=explicit_root)
    except SystemExit as e:
        err(f"local check skipped: {e}")

    checked_any = False
    all_confidences: set[str] = set()
    for i, field in enumerate(fields):
        if i > 0:
            print()
        print(f"field: {field}")
        field_checked, field_confidences = check_field(
            field,
            root,
            args.operator_namespace,
            args.secret_name,
            args.pull_secret_name,
            args.registry,
            args.context,
        )
        checked_any |= field_checked
        all_confidences |= field_confidences

    print()
    if not checked_any:
        err(
            "No source could be checked for any field (no local values.yaml "
            "and no readable cluster secrets). This is an access problem, "
            "not a finding -- fix access and retry."
        )
        return 3

    if CONFIDENCE_HIGH in all_confidences:
        err(
            "High-confidence whitespace contamination found in at least one "
            "field. Re-seed the affected values.yaml field(s) with "
            "`echo -n \"<value>\" | base64 | tr -d '\\n'` (both -n and the "
            "trailing tr matter), then re-run the install/upgrade so cluster "
            "secrets regenerate."
        )
        return 1

    if CONFIDENCE_LOW in all_confidences:
        err(
            "Only a low-confidence pattern was found, in a binary-capable "
            "field. This is plausibly genuine random binary, not corruption "
            "-- do NOT re-seed or rotate the value on this alone. Confirm "
            "the generation method with whoever set it first."
        )
        return 4

    print("All checked sources are clean.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
