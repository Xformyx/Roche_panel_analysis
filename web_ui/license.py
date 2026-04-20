"""License verification for Roche_nxt web UI.

Features are gated by a signed license file verified against an Ed25519 public
key that is baked into the image at build time.

Deployment modes
----------------
- **DEV_MODE** (env `DEV_MODE=1`): signature verification is skipped entirely
  and feature flags fall back to the old `ENABLE_*` env vars (or all-on when
  unset). Intended for internal development and self-hosted debugging.
- **Production**: a signed `license.json` must be present at `LICENSE_PATH`
  (default `/roche_nxt/license/license.json`). Any tampering or expiry causes
  the server to fail startup.

A license file looks like:

    {
      "customer": "ABC Hospital",
      "issued":   "2026-04-20",
      "expires":  "2027-04-20",
      "features": { "longitudinal": true, "igv": true, "hg19_view": false },
      "signature": "<base64 Ed25519 over the canonical JSON payload>"
    }

The "canonical payload" is `json.dumps(payload_without_signature, sort_keys=True,
separators=(",",":"))`. Both `tools/issue_license.py` and this verifier use the
exact same canonicalisation — keep them in sync.
"""

from __future__ import annotations

import base64
import json
import logging
import os
from datetime import date
from typing import Any, Dict, Optional

log = logging.getLogger("roche_nxt.license")

# Feature keys the application understands. Adding a new feature:
#   1. add it here and to FEATURE_DEFAULTS,
#   2. reference FEATURES["name"] from app.py,
#   3. (optional) include a default in tools/issue_license.py.
ALL_FEATURES = ("longitudinal", "igv", "hg19_view")
FEATURE_DEFAULTS = {k: False for k in ALL_FEATURES}

# Where the signed license file lives inside the container.
LICENSE_PATH = os.environ.get("LICENSE_PATH", "/roche_nxt/license/license.json")

# Public key location. Default is the file baked in at build time; override with
# LICENSE_PUBKEY_FILE or LICENSE_PUBKEY_B64 to swap without rebuilding.
_DEFAULT_PUBKEY_FILE = os.path.join(os.path.dirname(__file__), "_vendor_keys", "license_pubkey.b64")
PUBKEY_FILE = os.environ.get("LICENSE_PUBKEY_FILE", _DEFAULT_PUBKEY_FILE)
PUBKEY_B64_OVERRIDE = os.environ.get("LICENSE_PUBKEY_B64", "").strip()


class LicenseError(RuntimeError):
    """Raised when a production license is missing, invalid, or expired."""


def _dev_mode() -> bool:
    return os.environ.get("DEV_MODE", "").lower() in ("1", "true", "yes")


def _env_feature_fallback() -> Dict[str, bool]:
    """When DEV_MODE is on, honour the legacy ENABLE_* env vars (default on)."""
    def env_bool(name: str, default: bool = True) -> bool:
        raw = os.environ.get(name)
        if raw is None:
            return default
        return raw.lower() in ("true", "1", "yes")

    return {
        "longitudinal": env_bool("ENABLE_LONGITUDINAL", True),
        "igv":          env_bool("ENABLE_IGV", True),
        "hg19_view":    env_bool("ENABLE_HG19_VIEW", True),
    }


def _canonical_payload(data: Dict[str, Any]) -> bytes:
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _load_pubkey_b64() -> str:
    if PUBKEY_B64_OVERRIDE:
        return PUBKEY_B64_OVERRIDE
    if os.path.isfile(PUBKEY_FILE):
        with open(PUBKEY_FILE, "r") as f:
            return f.read().strip()
    raise LicenseError(
        f"License public key not available (looked at {PUBKEY_FILE} and env LICENSE_PUBKEY_B64)."
    )


def _verify_license_file() -> Dict[str, Any]:
    try:
        from nacl.exceptions import BadSignatureError
        from nacl.signing import VerifyKey
    except ImportError as e:
        raise LicenseError(f"PyNaCl is required for license verification: {e}")

    if not os.path.isfile(LICENSE_PATH):
        raise LicenseError(f"License file missing: {LICENSE_PATH}")

    with open(LICENSE_PATH, "r") as f:
        raw = json.load(f)

    sig_b64 = raw.pop("signature", None)
    if not sig_b64:
        raise LicenseError("License is missing a 'signature' field")

    try:
        sig = base64.b64decode(sig_b64)
    except Exception as e:
        raise LicenseError(f"License signature not valid base64: {e}")

    pubkey_b64 = _load_pubkey_b64()
    try:
        vk = VerifyKey(base64.b64decode(pubkey_b64))
    except Exception as e:
        raise LicenseError(f"Baked-in public key is invalid: {e}")

    try:
        vk.verify(_canonical_payload(raw), sig)
    except BadSignatureError:
        raise LicenseError(
            "License signature does NOT match. The file was either edited "
            "or signed with a key that does not match the installed public key."
        )

    today_s = date.today().isoformat()
    issued = raw.get("issued") or ""
    expires = raw.get("expires") or ""
    if expires and expires < today_s:
        raise LicenseError(f"License expired on {expires}")
    if issued and issued > today_s:
        raise LicenseError(f"License is not yet valid (issued={issued})")

    fmap = raw.get("features") or {}
    if not isinstance(fmap, dict):
        raise LicenseError("'features' must be a JSON object")

    features = {k: bool(fmap.get(k, FEATURE_DEFAULTS[k])) for k in ALL_FEATURES}

    return {
        "features": features,
        "customer": str(raw.get("customer") or ""),
        "issued": issued,
        "expires": expires,
    }


def load() -> Dict[str, Any]:
    """Return license info suitable for the Flask app.

    Keys:
      features:  {longitudinal: bool, igv: bool, hg19_view: bool}
      customer:  str (empty in dev mode)
      issued:    ISO date or ""
      expires:   ISO date or ""
      dev_mode:  bool
    """
    if _dev_mode():
        info = {
            "features": _env_feature_fallback(),
            "customer": "DEV (bypass)",
            "issued": "",
            "expires": "",
            "dev_mode": True,
        }
        log.warning("DEV_MODE=1: license verification bypassed; features=%s", info["features"])
        return info

    lic = _verify_license_file()
    lic["dev_mode"] = False
    log.info(
        "License OK — customer=%r, issued=%s, expires=%s, features=%s",
        lic["customer"], lic["issued"], lic["expires"], lic["features"],
    )
    return lic


__all__ = ["load", "LicenseError", "ALL_FEATURES", "LICENSE_PATH"]
