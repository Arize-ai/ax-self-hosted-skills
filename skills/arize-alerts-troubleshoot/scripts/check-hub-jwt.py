#!/usr/bin/env python3
"""check-hub-jwt.py -- Detect encoding corruption in the Arize hub license JWT.

Diagnoses ImagePullBackOff / 401 Unauthorized against the Arize image hub
(default ch.hub.arize.com) caused by a malformed ``hubJwt``: most commonly a
stray newline or other whitespace baked into the base64 payload because the
seeding pipeline dropped ``echo -n`` or ``tr -d '\\n'`` (see "Seed hubJwt
(license JWT)" in the distribution docs). Such a JWT still looks fine under
casual inspection -- it is valid base64, and its payload segment still
decodes as JSON with an unexpired-looking `exp`/`iat` -- so it is easy to
misdiagnose as a licensing/entitlement problem instead of an encoding bug.

This script never prints the JWT, the secret, or any decoded credential
bytes. It reports only: whether whitespace contamination was found, which
control character it was, and its byte offset.

Usage:
  check-hub-jwt.py [--distribution-root <path>] [--operator-namespace <ns>]
                    [--secret-name <name>] [--registry <host>] [--context <ctx>]

Exit codes:
  0  all available sources are clean (no whitespace contamination)
  1  contamination found in at least one source
  2  usage / invalid args
  3  no source available to check (no local values.yaml hubJwt AND cluster
     secret unreadable) -- not a finding, fix access and retry
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

WHITESPACE_NAMES = {
    0x09: "TAB",
    0x0A: "LF",
    0x0D: "CR",
    0x0B: "VT",
    0x0C: "FF",
    0x20: "SPACE",
}


def err(msg: str) -> None:
    print(msg, file=sys.stderr)


def find_whitespace(data: bytes) -> list[tuple[int, str]]:
    """Return (offset, name) for every whitespace/control byte found."""
    hits = []
    for i, b in enumerate(data):
        if b in WHITESPACE_NAMES:
            hits.append((i, WHITESPACE_NAMES[b]))
    return hits


def report_source(label: str, decoded: bytes) -> bool:
    """Print a pass/fail report for one decoded credential. Returns True if clean."""
    hits = find_whitespace(decoded)
    segments = decoded.split(b".")
    looks_like_jwt = len(segments) == 3

    print(f"source: {label}")
    print(f"  length: {len(decoded)} bytes")
    print(f"  looks_like_jwt (3 dot-separated segments): {looks_like_jwt}")

    if not hits:
        print("  whitespace_contamination: none")
        return True

    print(f"  whitespace_contamination: {len(hits)} byte(s) found")
    for offset, name in hits[:10]:
        at_end = offset >= len(decoded) - 2
        loc = "near end" if at_end else "embedded"
        print(f"    - {name} at byte offset {offset}/{len(decoded)} ({loc})")
    if len(hits) > 10:
        print(f"    ... and {len(hits) - 10} more")
    print(
        "  likely cause: seeding pipeline used `echo` instead of `echo -n`, "
        "or skipped `tr -d '\\n'` on the base64 output, embedding a newline "
        "or space inside the encoded value."
    )
    return False


def decode_b64_relaxed(raw: str) -> bytes:
    """Decode base64 that may itself contain accidental whitespace before the
    payload was produced (e.g. line-wrapped). Standard b64decode already
    ignores embedded newlines in the *encoded* text, which is correct --
    we want to inspect the *decoded* bytes, not the encoding wrapper."""
    return base64.b64decode(raw, validate=False)


def check_local_values_yaml(root: pathlib.Path) -> bytes | None:
    values_path = root / "values.yaml"
    if not values_path.is_file():
        err(f"local check skipped: no values.yaml at {values_path}")
        return None

    hub_jwt_b64 = None
    for line in values_path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if stripped.startswith("hubJwt:"):
            value = stripped[len("hubJwt:"):].strip()
            value = value.strip('"').strip("'")
            hub_jwt_b64 = value
            break

    if not hub_jwt_b64:
        err(f"local check skipped: no hubJwt key found in {values_path}")
        return None

    try:
        return decode_b64_relaxed(hub_jwt_b64)
    except binascii.Error as e:
        err(f"local hubJwt in {values_path} is not valid base64: {e}")
        return None


def check_cluster_secret(
    namespace: str, secret_name: str, registry: str, context: str | None
) -> bytes | None:
    cmd = [str(SAFE_KUBECTL)]
    if context:
        cmd += ["--context", context]
    cmd += [
        "-n",
        namespace,
        "get",
        "secret",
        secret_name,
        "-o",
        r"jsonpath={.data.\.dockerconfigjson}",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        err(f"cluster check skipped: could not run safe-kubectl.sh: {e}")
        return None

    if proc.returncode != 0:
        err(
            f"cluster check skipped: could not read secret/{secret_name} in "
            f"namespace {namespace}: {proc.stderr.strip()}"
        )
        return None

    raw = proc.stdout.strip()
    if not raw:
        err(f"cluster check skipped: secret/{secret_name} has no .dockerconfigjson data")
        return None

    try:
        dockerconfig = json.loads(decode_b64_relaxed(raw))
    except (binascii.Error, json.JSONDecodeError) as e:
        err(f"cluster check skipped: could not decode .dockerconfigjson: {e}")
        return None

    auths = dockerconfig.get("auths", {})
    creds = auths.get(registry)
    if creds is None:
        err(
            f"cluster check skipped: no auths entry for registry '{registry}' "
            f"in secret/{secret_name} (found: {', '.join(auths) or 'none'})"
        )
        return None

    auth_b64 = creds.get("auth", "")
    if not auth_b64:
        err(f"cluster check skipped: auths['{registry}'].auth is empty")
        return None

    try:
        decoded = decode_b64_relaxed(auth_b64)
    except binascii.Error as e:
        err(f"cluster check skipped: auth field is not valid base64: {e}")
        return None

    # decoded is "username:password" (docker basic-auth convention). The
    # password is the credential actually presented to the registry.
    if b":" not in decoded:
        err("cluster check skipped: decoded auth has no ':' separator")
        return None
    _, _, password = decoded.partition(b":")
    return password


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--distribution-root", "--docs-root", dest="distribution_root")
    parser.add_argument(
        "--operator-namespace",
        default=os.environ.get("OPERATOR_NS", "arize-operator"),
    )
    parser.add_argument("--secret-name", default="hub-json-key")
    parser.add_argument("--registry", default="ch.hub.arize.com")
    parser.add_argument("--context")
    args = parser.parse_args()

    explicit_root = None
    if args.distribution_root:
        explicit_root = pathlib.Path(args.distribution_root)

    root = None
    try:
        root = distribution.resolve_distribution_root(explicit=explicit_root)
    except SystemExit as e:
        err(f"local check skipped: {e}")

    checked_any = False
    clean = True

    if root is not None:
        local_decoded = check_local_values_yaml(root)
        if local_decoded is not None:
            checked_any = True
            clean &= report_source(f"values.yaml hubJwt ({root / 'values.yaml'})", local_decoded)

    cluster_decoded = check_cluster_secret(
        args.operator_namespace, args.secret_name, args.registry, args.context
    )
    if cluster_decoded is not None:
        checked_any = True
        clean &= report_source(
            f"cluster secret {args.operator_namespace}/{args.secret_name} "
            f"(auths['{args.registry}'].auth password)",
            cluster_decoded,
        )

    if not checked_any:
        err(
            "No source could be checked (no local values.yaml hubJwt and no "
            "readable cluster pull secret). This is an access problem, not a "
            "finding -- fix access and retry."
        )
        return 3

    if not clean:
        err(
            "Whitespace contamination found. Re-seed hubJwt with "
            "`echo -n \"<JWT>\" | base64 | tr -d '\\n'` (both -n and the "
            "trailing tr matter), update values.yaml, and re-run the "
            "install/upgrade so the pull secret is regenerated."
        )
        return 1

    print("All checked sources are clean.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
