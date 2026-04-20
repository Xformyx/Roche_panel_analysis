# Roche_nxt — Licensing & Deployment Guide

This document describes how feature licensing works in Roche_nxt and how to
deploy the product to customers in a way that prevents them from enabling
features they have not paid for, without making your internal development
flow more painful.

> **일상 운영 / 고객 배포 / 장애 대응 런북**은 별도 문서
> [`docs/OPERATIONS.md`](docs/OPERATIONS.md) 를 참고하세요. 이 문서는
> 라이선스 **메커니즘** 자체에 초점을 맞춥니다.

TL;DR

- **Internal development** (your laptop / lab server): keep using
  `docker compose up -d`. `DEV_MODE=1` in `.env` bypasses license checks
  and activates every feature.
- **Customer deployment** (on-prem, air-gapped): use
  `docker-compose.prod.yml`. It refuses to start without a signed
  `license.json` that you issue offline.
- Feature flags live in the license, not in `.env`. Customers cannot flip
  them on by editing `.env` or the compose file.


## 1. One-time setup — create your signing keypair

Do this **once**, on a secure machine that you control. The private key
must never leave that machine.

```bash
make keygen
```

This generates:

| File | Purpose | Keep where |
|------|---------|------------|
| `~/.roche_nxt_keys/license_signing_key.b64` | Private signing key | Offline backup (USB + encrypted cloud). Never share. |
| `~/.roche_nxt_keys/license_pubkey.b64`      | Public verify key   | Copied into the image build context automatically. |
| `web_ui/_vendor_keys/license_pubkey.b64`    | Baked into the image | Commit to git. |

After `make keygen` you **must** rebuild the web image so the new public
key is embedded:

```bash
make build-web
```

> **Warning**: re-running `make keygen --force` invalidates every license
> already issued with the previous key. Only regenerate if the old key is
> compromised, and expect to rebuild + redeploy the image everywhere.


## 2. Issuing a license for a customer

```bash
# Full-feature, 1-year license
make license \
    CUSTOMER="ABC Hospital" \
    EXPIRES=2027-04-20 \
    FEATURES=longitudinal,igv,hg19_view

# Baseline-only license (no longitudinal), 6 months
make license \
    CUSTOMER="XYZ Lab" \
    EXPIRES=2026-10-20 \
    FEATURES=igv

# Perpetual license (no expiry). Use sparingly — you lose the
# natural renewal cadence this gives you.
make license \
    CUSTOMER="Internal Server" \
    EXPIRES=never \
    FEATURES=longitudinal,igv,hg19_view
#   (equivalent: NO_EXPIRY=1 instead of EXPIRES=never)
```

Output: `deploy/licenses/<customer_slug>.json` — a ~500-byte JSON file you
deliver to the customer via email, SFTP, USB, etc. It is signed, so even
the customer cannot modify it without being detected at server startup.

Supported feature keys (keep in sync with `web_ui/license.py::ALL_FEATURES`):

- `longitudinal` — baseline/followup workflow
- `igv` — embedded IGV viewer in Variant Review
- `hg19_view` — hg19 coordinate toggle in Variant Review


## 3. Air-gapped customer deployment

You need to ship three things to the customer:

1. **Docker image tarball** (`deploy/images/roche_nxt_web.tar.gz`)
2. **Compose file** (`docker-compose.prod.yml`) and `.env.example`
3. **Customer's license.json** (e.g. `abc_hospital.json`)

All three are bundled by:

```bash
make prod-save
```

Output is placed in `deploy/images/` and `deploy/package/`.

On the customer site:

```bash
docker load < roche_nxt_web.tar.gz
docker load < roche_nxt_analysis.tar.gz   # if shipped

mkdir -p license
cp abc_hospital.json license/license.json

cp .env.example .env
# edit .env — set WEB_PORT, UID/GID, FASTQ_HOST_DIR, BED_HOST_DIR
# do NOT set DEV_MODE=1

docker compose -f docker-compose.prod.yml up -d
```

If anything about the license is wrong (missing file, bad signature, expired
date, unknown public key) the web container exits with a clear error
message. The customer cannot work around this without the signing key.


## 4. Extending a customer's features later

No rebuild needed. Re-issue the license with the new feature set and
deliver the new JSON:

```bash
make license \
    CUSTOMER="ABC Hospital" \
    EXPIRES=2027-04-20 \
    FEATURES=longitudinal,igv,hg19_view
```

Customer drops the file at `/roche_nxt/license/license.json` and restarts
the web container:

```bash
docker compose -f docker-compose.prod.yml restart roche-nxt-web
```

Takes under a minute.


## 5. Internal development flow — unchanged

On your own machines, keep doing:

```bash
docker compose up -d          # uses docker-compose.yml, DEV_MODE=1 baked in
```

`web_ui/` is bind-mounted for hot reload, license checks are skipped, all
features are on. You do not need a license file at all. If `.env` has
`DEV_MODE=1` (the default), the `ENABLE_*` fallbacks still work if you
want to flip individual features off for testing.


## 6. What this protects against (and doesn't)

| Threat | Mitigation |
|--------|-----------|
| Customer edits `.env` to enable paid features | ✅ Blocked — features read only from signed license |
| Customer edits `license.json` | ✅ Blocked — signature verification fails |
| Customer back-dates system clock | ⚠ Partially — works while the clock is rewound; renew annually |
| Customer runs `docker cp` to read `app.py` | ❌ Not blocked — source lives inside the image as plain Python |
| Dedicated reverse-engineering with IDA/Ghidra | ❌ Not blocked — requires commercial obfuscation (PyArmor, Nuitka) |

If a customer ever warrants the next level of protection, the PyArmor /
Nuitka step can be added to `build-web` without touching anything else in
this licensing flow.


## 7. Key rotation / disaster recovery

- **Lost private key** → generate a new one with `make keygen --force`,
  rebuild and redeploy the image to every customer, then reissue their
  licenses. Plan this for a maintenance window.
- **Leaked private key** → same drill. Also rotate the image tag to mark
  the old builds as untrusted.
- **Customer needs a replacement license** (corrupted file, clock reset,
  etc.) → just reissue and send.
