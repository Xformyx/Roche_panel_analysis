#!/usr/bin/env python3
"""Generate a fresh Ed25519 keypair for Roche_nxt license signing.

USAGE
-----
    python tools/keygen.py [--out-dir DIR]

Outputs:
  <out>/license_signing_key.b64  - private key (KEEP SECRET, back up offline!)
  <out>/license_pubkey.b64       - public key (bake into the image)

The public key file is copied into web_ui/_vendor_keys/license_pubkey.b64
automatically so that a subsequent `docker compose build` bakes it in.

Run this ONCE per product line. After that, use tools/issue_license.py to
issue per-customer licenses; you only need to re-run keygen if the signing
key is compromised (in which case every deployed installation will need a
re-built image with the new public key).
"""

from __future__ import annotations

import argparse
import base64
import os
import shutil
import sys


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "--out-dir", default=os.path.expanduser("~/.roche_nxt_keys"),
        help="Directory to place the generated keys (default: ~/.roche_nxt_keys)",
    )
    ap.add_argument(
        "--force", action="store_true",
        help="Overwrite an existing signing key (dangerous — old licenses still work).",
    )
    ap.add_argument(
        "--bake-into",
        default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                             "web_ui", "_vendor_keys", "license_pubkey.b64"),
        help="Path where the public key will also be copied so the next image build picks it up.",
    )
    args = ap.parse_args()

    try:
        from nacl.signing import SigningKey
    except ImportError:
        print("ERROR: PyNaCl is required. Install with: pip install PyNaCl", file=sys.stderr)
        return 2

    os.makedirs(args.out_dir, exist_ok=True)
    priv_path = os.path.join(args.out_dir, "license_signing_key.b64")
    pub_path = os.path.join(args.out_dir, "license_pubkey.b64")

    if os.path.isfile(priv_path) and not args.force:
        print(f"ERROR: {priv_path} already exists. Use --force to overwrite.", file=sys.stderr)
        print("       Overwriting invalidates every license that was signed with the old key.", file=sys.stderr)
        return 1

    sk = SigningKey.generate()
    vk = sk.verify_key

    priv_b64 = base64.b64encode(bytes(sk)).decode("ascii")
    pub_b64 = base64.b64encode(bytes(vk)).decode("ascii")

    with open(priv_path, "w") as f:
        f.write(priv_b64 + "\n")
    os.chmod(priv_path, 0o600)

    with open(pub_path, "w") as f:
        f.write(pub_b64 + "\n")

    if args.bake_into:
        os.makedirs(os.path.dirname(args.bake_into), exist_ok=True)
        shutil.copyfile(pub_path, args.bake_into)

    print("=== Roche_nxt license keypair generated ===")
    print(f"  Private key: {priv_path}   (mode 0600 — keep secret, back up offline)")
    print(f"  Public key : {pub_path}")
    if args.bake_into:
        print(f"  Baked into : {args.bake_into}")
        print()
        print("Next step: rebuild the web image to embed the new public key:")
        print("    docker compose build roche-nxt-web")
    return 0


if __name__ == "__main__":
    sys.exit(main())
