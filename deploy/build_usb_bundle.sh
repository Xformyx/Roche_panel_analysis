#!/usr/bin/env bash
#
# Roche_nxt — USB Bundle Builder (runs on the packager's online machine)
#
# Assembles a self-contained offline deployment bundle that a customer can
# copy onto a USB drive and install on an air-gapped server.
#
# Bundle layout produced
#   <out-dir>/
#     install.sh                    ← bootstrap (thin wrapper)
#     README.txt
#     SHA256SUMS
#     scripts/
#       offline_install.sh
#       install_docker.sh
#     docker/<distro>/*.deb|rpm     ← Docker offline packages (user-supplied)
#     images/
#       roche_nxt_web.tar.gz
#       roche_nxt_analysis.tar.gz
#     data/
#       roche_data.tar.gz           ← reference data (optional; see --with-data)
#     liftover/
#       hg38ToHg19.over.chain.gz    ← if present in data/liftover/
#     app/
#       docker-compose.yml          ← docker-compose.prod.yml renamed
#       .env.example
#     license/
#       license.json                ← --license <path>
#
# Usage
#   bash deploy/build_usb_bundle.sh \
#       --customer "ABC Hospital" \
#       --license deploy/licenses/abc_hospital.json \
#       --with-data \
#       [--docker-debs-dir ~/docker-debs/ubuntu-22.04] \
#       [--out deploy/usb]
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YEL=$'\033[1;33m'
    C_CYN=$'\033[0;36m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_BLD=""; C_RST=""
fi
log()  { echo "${C_CYN}[bundle]${C_RST} $*"; }
ok()   { echo "  ${C_GRN}✓${C_RST} $*"; }
warn() { echo "  ${C_YEL}!${C_RST} $*"; }
die()  { echo "  ${C_RED}✗ $*${C_RST}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Defaults / args
# ---------------------------------------------------------------------------
CUSTOMER=""
LICENSE_FILE=""
WITH_DATA=0
DOCKER_DEBS_DIR=""
DOCKER_TARGET_DISTRO=""
FETCH_DOCKER_DISTRO=""
OUT_DIR="${PROJECT_DIR}/deploy/usb"
SKIP_IMAGES=0
REFRESH_DATA=0
REFRESH_DOCKER=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --customer)         CUSTOMER="$2"; shift 2 ;;
        --license)          LICENSE_FILE="$2"; shift 2 ;;
        --with-data)        WITH_DATA=1; shift ;;
        --docker-debs-dir)  DOCKER_DEBS_DIR="$2"; shift 2 ;;
        --docker-distro)    DOCKER_TARGET_DISTRO="$2"; shift 2 ;;
        --fetch-docker)     FETCH_DOCKER_DISTRO="$2"; shift 2 ;;
        --out)              OUT_DIR="$2"; shift 2 ;;
        --skip-images)      SKIP_IMAGES=1; shift ;;
        --refresh-data)     REFRESH_DATA=1; shift ;;
        --refresh-docker)   REFRESH_DOCKER=1; shift ;;
        -h|--help)
            cat <<USAGE
Usage: bash $(basename "$0") --customer "NAME" --license <path> [OPTIONS]

Required:
  --customer NAME         Customer name (for README and filenames)
  --license PATH          Path to the signed license.json for this customer

Common:
  --with-data             Include reference data tarball (roche_data)
                          — adds ~140 GB to the bundle
  --docker-debs-dir DIR   Directory containing Docker .deb/.rpm files to stage
                          (one directory per target OS release). If you do not
                          have packages pre-staged, use --fetch-docker instead.
  --fetch-docker LIST     Auto-download Docker offline packages from the
                          internet for one or more target distros and stage
                          them. Comma-separated list, or "all".
                          Valid items: ubuntu-22.04 | ubuntu-24.04 |
                                       debian-12 | rhel-8 | rhel-9
                          Examples:
                              --fetch-docker ubuntu-22.04
                              --fetch-docker ubuntu-22.04,ubuntu-24.04,rhel-9
                              --fetch-docker all
                          Requires Docker on this packaging machine.
  --docker-distro NAME    Subdir under docker/ (e.g. ubuntu-22.04). Inferred
                          from --docker-debs-dir / --fetch-docker if omitted.
  --out DIR               Output directory (default: deploy/usb)
  --skip-images           Skip re-saving Docker images (reuse existing tarballs)
  --refresh-data          Force re-pack of data/roche_data.tar.gz even if it
                          already exists in the output dir (default: skip if
                          present — typically a few-hour operation).
  --refresh-docker        Force re-download of Docker offline packages even if
                          docker/<distro>/ already exists (default: skip if
                          present and non-empty).

Example:
  bash deploy/build_usb_bundle.sh \\
      --customer "ABC Hospital" \\
      --license deploy/licenses/abc_hospital.json \\
      --with-data \\
      --docker-debs-dir ~/docker-debs/ubuntu-22.04 \\
      --out /media/usb/roche_nxt_bundle

USAGE
            exit 0
            ;;
        *) die "Unknown arg: $1" ;;
    esac
done

[[ -n "$CUSTOMER" ]]     || die "--customer is required"
[[ -n "$LICENSE_FILE" ]] || die "--license is required"
[[ -f "$LICENSE_FILE" ]] || die "License file not found: $LICENSE_FILE"

log "Building USB bundle"
log "  Customer : $CUSTOMER"
log "  License  : $LICENSE_FILE"
log "  With data: $([[ $WITH_DATA -eq 1 ]] && echo yes || echo no)"
log "  Output   : $OUT_DIR"
echo ""

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
log "[1/8] Preflight checks"

command -v docker >/dev/null 2>&1 || die "docker is not installed on this machine."

for img in roche_nxt_web:latest roche_nxt_analysis:latest; do
    if [[ $SKIP_IMAGES -eq 0 ]]; then
        docker image inspect "$img" >/dev/null 2>&1 \
            || die "Image $img not found. Build first: make build"
    fi
done
ok "Docker and images available"

[[ -f "${PROJECT_DIR}/docker-compose.prod.yml" ]] \
    || die "docker-compose.prod.yml missing at project root."
[[ -f "${PROJECT_DIR}/.env.example" ]] \
    || die ".env.example missing at project root."
[[ -f "${PROJECT_DIR}/deploy/scripts/offline_install.sh" ]] \
    || die "deploy/scripts/offline_install.sh missing (did you run this from a fresh checkout?)."
ok "Project files present"

# Surgical cleanup: keep expensive cached artifacts (data tar, docker pkgs,
# image tarballs) and only wipe the small, always-rebuilt parts. This lets
# repeat runs reuse the slow downloads/packing.
mkdir -p "$OUT_DIR"/{scripts,images,app,license,data,liftover,docker}
rm -rf "${OUT_DIR}/scripts" "${OUT_DIR}/app" "${OUT_DIR}/license" \
       "${OUT_DIR}/liftover" "${OUT_DIR}/install.sh" \
       "${OUT_DIR}/README.txt" "${OUT_DIR}/SHA256SUMS"
mkdir -p "$OUT_DIR"/{scripts,app,license,liftover}
ok "Output directory prepared at $OUT_DIR (cached data/docker/images preserved)"

# ---------------------------------------------------------------------------
# Installer scripts + bootstrap
# ---------------------------------------------------------------------------
log "[2/8] Stage installer scripts"
install -m 0755 "${PROJECT_DIR}/deploy/scripts/offline_install.sh" "${OUT_DIR}/scripts/"
install -m 0755 "${PROJECT_DIR}/deploy/scripts/install_docker.sh"  "${OUT_DIR}/scripts/"
ok "scripts/ populated"

cat > "${OUT_DIR}/install.sh" <<'BOOTSTRAP'
#!/usr/bin/env bash
# Roche_nxt bootstrap installer (runs from USB root).
#
# This wrapper resolves its own absolute path, then hands off to the real
# installer that does the 11-step installation. If Docker isn't installed
# yet, the real installer will call install_docker.sh first.
set -Eeuo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $EUID -ne 0 ]]; then
    echo "This installer must run with root privileges."
    echo "    sudo bash $(basename "$0")"
    exit 1
fi
exec bash "${SELF_DIR}/scripts/offline_install.sh" --bundle-root "${SELF_DIR}" "$@"
BOOTSTRAP
chmod 0755 "${OUT_DIR}/install.sh"
ok "Top-level install.sh written"

# ---------------------------------------------------------------------------
# Docker images
# ---------------------------------------------------------------------------
log "[3/8] Save Docker images"
if [[ $SKIP_IMAGES -eq 1 ]]; then
    warn "Skipping image save (--skip-images)"
else
    echo "  Saving roche_nxt_web:latest..."
    docker save roche_nxt_web:latest | gzip > "${OUT_DIR}/images/roche_nxt_web.tar.gz"
    ok "roche_nxt_web.tar.gz ($(du -h "${OUT_DIR}/images/roche_nxt_web.tar.gz" | cut -f1))"

    if docker image inspect roche_nxt_analysis:latest >/dev/null 2>&1; then
        echo "  Saving roche_nxt_analysis:latest..."
        docker save roche_nxt_analysis:latest | gzip > "${OUT_DIR}/images/roche_nxt_analysis.tar.gz"
        ok "roche_nxt_analysis.tar.gz ($(du -h "${OUT_DIR}/images/roche_nxt_analysis.tar.gz" | cut -f1))"
    else
        warn "roche_nxt_analysis:latest not found — skipping (web-only deploy)"
    fi
fi

# ---------------------------------------------------------------------------
# App (compose + env template + Nextflow pipeline files)
# ---------------------------------------------------------------------------
log "[4/8] Stage app/"
cp "${PROJECT_DIR}/docker-compose.prod.yml" "${OUT_DIR}/app/docker-compose.yml"
cp "${PROJECT_DIR}/.env.example"            "${OUT_DIR}/app/.env.example"
ok "docker-compose.yml (prod) + .env.example staged"

# Nextflow pipeline files — must be present on the host so the analysis
# container can mount and run them.
mkdir -p "${OUT_DIR}/app/pipeline"
cp "${PROJECT_DIR}/main.nf"         "${OUT_DIR}/app/pipeline/"
cp "${PROJECT_DIR}/nextflow.config" "${OUT_DIR}/app/pipeline/"
cp -r "${PROJECT_DIR}/modules"      "${OUT_DIR}/app/pipeline/"
cp -r "${PROJECT_DIR}/workflows"    "${OUT_DIR}/app/pipeline/"
[[ -d "${PROJECT_DIR}/conf" ]] && cp -r "${PROJECT_DIR}/conf" "${OUT_DIR}/app/pipeline/"
NF_COUNT=$(find "${OUT_DIR}/app/pipeline" -name "*.nf" | wc -l)
ok "Nextflow pipeline staged (${NF_COUNT} .nf files + conf/)"

# ---------------------------------------------------------------------------
# License
# ---------------------------------------------------------------------------
log "[5/8] Stage license"
cp "$LICENSE_FILE" "${OUT_DIR}/license/license.json"
ok "license/license.json staged"

# ---------------------------------------------------------------------------
# Reference data (optional)
# ---------------------------------------------------------------------------
log "[6/8] Reference data"
DATA_TAR="${OUT_DIR}/data/roche_data.tar.gz"
if [[ $WITH_DATA -eq 1 ]]; then
    if [[ -f "$DATA_TAR" && $REFRESH_DATA -eq 0 ]]; then
        ok "Reusing cached data/roche_data.tar.gz ($(du -h "$DATA_TAR" | cut -f1)) — pass --refresh-data to rebuild"
    else
        [[ -f "$DATA_TAR" ]] && rm -f "$DATA_TAR"
        DATA_TARGET=""
        if [[ -L "${PROJECT_DIR}/data" ]]; then
            DATA_TARGET="$(readlink -f "${PROJECT_DIR}/data")"
        elif [[ -d "${PROJECT_DIR}/data" ]]; then
            DATA_TARGET="${PROJECT_DIR}/data"
        fi
        if [[ -z "$DATA_TARGET" || ! -d "$DATA_TARGET" ]]; then
            die "Reference data directory not found (PROJECT_DIR/data is missing or broken)."
        fi
        DATA_PARENT="$(dirname "$DATA_TARGET")"
        DATA_NAME="$(basename "$DATA_TARGET")"
        warn "Packing reference data — this may take a long time..."
        ( cd "$DATA_PARENT" && tar czf "$DATA_TAR" --transform "s|^${DATA_NAME}|roche_data|" "${DATA_NAME}" )
        ok "data/roche_data.tar.gz ($(du -h "$DATA_TAR" | cut -f1))"
    fi
else
    if [[ -f "$DATA_TAR" ]]; then
        warn "data/roche_data.tar.gz exists from a previous run but --with-data not given — leaving it in place."
    else
        warn "Skipping reference data (add --with-data or ship a separate tarball)"
    fi
fi

# Liftover (small, always ship if present)
if [[ -f "${PROJECT_DIR}/data/liftover/hg38ToHg19.over.chain.gz" ]]; then
    cp "${PROJECT_DIR}/data/liftover/hg38ToHg19.over.chain.gz" "${OUT_DIR}/liftover/"
    ok "liftover chain staged"
else
    warn "No liftover chain at data/liftover/ — hg19_view feature will need manual setup"
fi

# ---------------------------------------------------------------------------
# Docker offline packages
# ---------------------------------------------------------------------------
log "[7/8] Docker offline packages"

# If --fetch-docker was provided, download packages for each requested
# distro on-the-fly. The "all" shortcut expands to the known set.
if [[ -n "$FETCH_DOCKER_DISTRO" ]]; then
    if [[ -n "$DOCKER_DEBS_DIR" ]]; then
        die "--fetch-docker and --docker-debs-dir are mutually exclusive."
    fi

    FETCH_LIST="$FETCH_DOCKER_DISTRO"
    if [[ "$FETCH_LIST" == "all" ]]; then
        FETCH_LIST="ubuntu-22.04,ubuntu-24.04,debian-12,rhel-8,rhel-9"
    fi

    IFS=',' read -r -a _DISTROS <<<"$FETCH_LIST"
    for d in "${_DISTROS[@]}"; do
        d="$(echo "$d" | xargs)"   # trim
        [[ -z "$d" ]] && continue
        DEST="${OUT_DIR}/docker/${d}"
        # Reuse cached packages if present (and not forced refresh).
        shopt -s nullglob
        _existing=("$DEST"/*.deb "$DEST"/*.rpm)
        shopt -u nullglob
        if [[ -d "$DEST" && ${#_existing[@]} -gt 0 && $REFRESH_DOCKER -eq 0 ]]; then
            ok "Reusing cached docker/${d}/ (${#_existing[@]} pkgs) — pass --refresh-docker to re-download"
            continue
        fi
        rm -rf "$DEST"
        mkdir -p "$DEST"
        log "Auto-downloading Docker packages for ${d}..."
        if ! bash "${PROJECT_DIR}/deploy/scripts/fetch_docker_packages.sh" \
                "$d" "$DEST"; then
            die "Failed to fetch Docker packages for ${d}. Check internet access / Docker on this machine."
        fi
        ok "Staged Docker packages → docker/${d}/"
    done

    # Skip the legacy single-dir staging path below (already done above).
    DOCKER_FETCHED_MULTI=1
fi

if [[ -z "${DOCKER_FETCHED_MULTI:-}" ]]; then
    if [[ -n "$DOCKER_DEBS_DIR" ]]; then
        [[ -d "$DOCKER_DEBS_DIR" ]] || die "Docker packages dir not found: $DOCKER_DEBS_DIR"
        # `cp dir/*` fails when the directory exists but is empty (glob matches nothing).
        shopt -s nullglob
        _deb_glob=("${DOCKER_DEBS_DIR}"/*)
        shopt -u nullglob
        if [[ ${#_deb_glob[@]} -eq 0 ]]; then
            die "Docker packages dir is empty: $DOCKER_DEBS_DIR — add *.deb or *.rpm files (see docs/OFFLINE_INSTALL.md) or omit --docker-debs-dir if the target server already has Docker."
        fi
        if [[ -z "$DOCKER_TARGET_DISTRO" ]]; then
            DOCKER_TARGET_DISTRO="$(basename "$DOCKER_DEBS_DIR")"
        fi
        DEST="${OUT_DIR}/docker/${DOCKER_TARGET_DISTRO}"
        shopt -s nullglob
        _existing=("$DEST"/*.deb "$DEST"/*.rpm)
        shopt -u nullglob
        if [[ -d "$DEST" && ${#_existing[@]} -gt 0 && $REFRESH_DOCKER -eq 0 ]]; then
            ok "Reusing cached docker/${DOCKER_TARGET_DISTRO}/ — pass --refresh-docker to re-stage"
        else
            rm -rf "$DEST"
            mkdir -p "$DEST"
            cp -r "${DOCKER_DEBS_DIR}"/* "$DEST/"
            ok "Staged packages from ${DOCKER_DEBS_DIR} → docker/${DOCKER_TARGET_DISTRO}/"
        fi
    else
        cat > "${OUT_DIR}/docker/README.txt" <<'EOF'
No Docker offline packages were staged by the packager.

If the target server already has Docker Engine + Compose v2 installed,
nothing more is needed — the installer will detect it.

Otherwise, re-run the bundle builder with one of:
    --fetch-docker ubuntu-22.04,ubuntu-24.04,rhel-9   (auto-download)
    --fetch-docker all                                 (all known distros)
    --docker-debs-dir /path/to/debs                    (manually staged dir)

Download instructions are in docs/OFFLINE_INSTALL.md.
EOF
        warn "No Docker packages staged. Customer must already have Docker."
    fi
fi

# ---------------------------------------------------------------------------
# README + checksums
# ---------------------------------------------------------------------------
# Drop the temporary download cache before computing checksums / packaging.
if [[ -d "${OUT_DIR}/_fetched_docker_pkgs" ]]; then
    rm -rf "${OUT_DIR}/_fetched_docker_pkgs"
fi

log "[8/8] README + checksums"

SAFE_CUST="$(echo "$CUSTOMER" | tr 'A-Z ' 'a-z_' | tr -cd '[:alnum:]_-')"
cat > "${OUT_DIR}/README.txt" <<EOF
Roche_nxt Offline Installation Bundle
======================================
Customer : ${CUSTOMER}
Built    : $(date -u +"%Y-%m-%d %H:%M:%SZ")
Builder  : $(hostname) / $(id -un)

Contents
--------
  install.sh                 Run this. (sudo bash install.sh)
  scripts/                   Installer engine + Docker offline installer
  images/                    Docker image tarballs
  app/                       docker-compose.yml (prod) + .env.example
  license/license.json       Customer-specific signed license
  data/                      Reference data (if --with-data was used)
  liftover/                  hg38↔hg19 chain (for hg19_view feature)
  docker/<distro>/           Docker .deb or .rpm packages (if staged)
  SHA256SUMS                 Integrity checksums for every file above

Install (on the target server)
------------------------------
  1. Mount the USB drive:
         sudo mkdir -p /mnt/usb
         sudo mount /dev/sdX1 /mnt/usb
  2. Run the installer:
         cd /mnt/usb/<bundle-dir>
         sudo bash install.sh
  3. Watch the 11-step output. Fix any FAIL message and re-run.
  4. When it finishes, open:   http://<server-ip>:8080/

For details see docs/OFFLINE_INSTALL.md inside the project source tree,
or LICENSE.md for licensing info.
EOF
ok "README.txt written"

# SHA256 sums for integrity verification
( cd "$OUT_DIR" && find . -type f ! -name SHA256SUMS -print0 \
    | xargs -0 sha256sum > SHA256SUMS )
ok "SHA256SUMS written ($(wc -l < "${OUT_DIR}/SHA256SUMS") files)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL_SIZE="$(du -sh "$OUT_DIR" | cut -f1)"
echo ""
echo "${C_GRN}${C_BLD}============================================================${C_RST}"
echo "${C_GRN}${C_BLD}  Bundle ready — total ${TOTAL_SIZE}${C_RST}"
echo "${C_GRN}${C_BLD}============================================================${C_RST}"
echo ""
echo "  Location: ${OUT_DIR}"
echo ""
echo "  Copy to USB:"
echo "      rsync -aP ${OUT_DIR}/ /media/\$USER/<USB-name>/"
echo "  Or:"
echo "      tar -C ${OUT_DIR} -cf /media/\$USER/<USB-name>/roche_nxt_bundle.tar ."
echo ""
echo "  Customer install: sudo bash install.sh (from USB root)"
echo ""
