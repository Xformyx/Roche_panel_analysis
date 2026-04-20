#!/usr/bin/env python3
"""Issue a signed Roche_nxt license.json for a customer.

EXAMPLES
--------
    # Full-feature license valid for 1 year
    python tools/issue_license.py \\
        --customer "ABC Hospital" \\
        --expires  2027-04-20 \\
        --features longitudinal,igv,hg19_view \\
        --out      deploy/licenses/abc_hospital.json

    # Baseline-only license (no longitudinal), 6 months
    python tools/issue_license.py \\
        --customer "XYZ Lab" \\
        --expires  2026-10-20 \\
        --features igv \\
        --out      deploy/licenses/xyz_lab.json

The generated file must be delivered to the customer and placed at
/roche_nxt/license/license.json in their deployment (see LICENSE.md).
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from datetime import date

# Keep in sync with web_ui/license.py
ALL_FEATURES = ("longitudinal", "igv", "hg19_view")


def _canonical_payload(data):
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--customer", required=True, help="Customer display name (e.g. 'ABC Hospital')")
    ap.add_argument("--issued", default=date.today().isoformat(),
                    help="Issue date YYYY-MM-DD (default: today)")
    g_exp = ap.add_mutually_exclusive_group(required=True)
    g_exp.add_argument("--expires", help="Expiry date YYYY-MM-DD (inclusive)")
    g_exp.add_argument("--no-expiry", action="store_true",
                       help="Issue a perpetual license (no expiry). Use with care.")
    ap.add_argument("--features", required=True,
                    help="Comma-separated feature list. Valid keys: " + ",".join(ALL_FEATURES))
    ap.add_argument("--private-key",
                    default=os.path.expanduser("~/.roche_nxt_keys/license_signing_key.b64"),
                    help="Path to the base64 Ed25519 signing key created by tools/keygen.py")
    ap.add_argument("--out", required=True, help="Output path for the signed license JSON")
    args = ap.parse_args()

    try:
        from nacl.signing import SigningKey
    except ImportError:
        print("ERROR: PyNaCl is required. Install with: pip install PyNaCl", file=sys.stderr)
        return 2

    # Validate features
    requested = [f.strip() for f in args.features.split(",") if f.strip()]
    unknown = [f for f in requested if f not in ALL_FEATURES]
    if unknown:
        print(f"ERROR: unknown feature(s): {unknown}. Valid: {list(ALL_FEATURES)}", file=sys.stderr)
        return 1
    features = {k: (k in requested) for k in ALL_FEATURES}

    try:
        d_issued = date.fromisoformat(args.issued)
    except ValueError as e:
        print(f"ERROR: invalid --issued date: {e}", file=sys.stderr)
        return 1
    d_expires = None
    if not args.no_expiry:
        try:
            d_expires = date.fromisoformat(args.expires)
        except ValueError as e:
            print(f"ERROR: invalid --expires date: {e}", file=sys.stderr)
            return 1
        if d_expires < d_issued:
            print("ERROR: --expires is before --issued", file=sys.stderr)
            return 1

    # Load signing key
    if not os.path.isfile(args.private_key):
        print(f"ERROR: signing key not found: {args.private_key}", file=sys.stderr)
        print("       Run tools/keygen.py first to create one.", file=sys.stderr)
        return 1
    with open(args.private_key, "r") as f:
        sk = SigningKey(base64.b64decode(f.read().strip()))

    payload = {
        "customer": args.customer,
        "issued": d_issued.isoformat(),
        "expires": "" if d_expires is None else d_expires.isoformat(),
        "features": features,
    }
    sig = sk.sign(_canonical_payload(payload)).signature
    payload_signed = dict(payload)
    payload_signed["signature"] = base64.b64encode(sig).decode("ascii")

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(payload_signed, f, indent=2, ensure_ascii=False, sort_keys=True)
        f.write("\n")

    print(f"Wrote license: {args.out}")
    print(f"  Customer : {args.customer}")
    print(f"  Issued   : {d_issued}")
    print(f"  Expires  : {d_expires if d_expires is not None else '(never — perpetual license)'}")
    print(f"  Features : {', '.join(k for k, v in features.items() if v) or '(none)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
