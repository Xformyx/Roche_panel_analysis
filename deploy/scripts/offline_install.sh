#!/usr/bin/env bash
#
# Roche_nxt — Offline Installer (runs on the customer's target server)
#
# This script is the core installation engine. It is invoked by the
# top-level `install.sh` that lives on the USB root.
#
# Design goals
#   - Step-by-step: each step prints [i/N] header, [OK]/[SKIP]/[FAIL] marker.
#   - Idempotent: re-running after a partial failure resumes safely.
#   - Loud on failure: halts with actionable guidance, never silent.
#   - Zero internet: everything comes from the USB bundle.
#
# Usage
#   sudo bash scripts/offline_install.sh [--bundle-root <dir>] [--install-dir <dir>]
#
# Defaults
#   --bundle-root = directory containing this script's parent (the USB)
#   --install-dir = /opt/roche_nxt
#

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Visual helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'
    C_GRN=$'\033[0;32m'
    C_YEL=$'\033[1;33m'
    C_CYN=$'\033[0;36m'
    C_BLD=$'\033[1m'
    C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_BLD=""; C_RST=""
fi

TOTAL_STEPS=11
CUR_STEP=0

step() {
    CUR_STEP=$((CUR_STEP + 1))
    echo ""
    echo "${C_BLD}${C_CYN}[${CUR_STEP}/${TOTAL_STEPS}] $*${C_RST}"
    echo "${C_CYN}$(printf '─%.0s' {1..70})${C_RST}"
}
ok()    { echo "  ${C_GRN}✓${C_RST} $*"; }
skip()  { echo "  ${C_YEL}○${C_RST} $*"; }
warn()  { echo "  ${C_YEL}!${C_RST} $*"; }
fail()  { echo "  ${C_RED}✗ $*${C_RST}" >&2; }

die() {
    fail "$1"
    echo ""
    echo "${C_RED}${C_BLD}Installation halted at step ${CUR_STEP}/${TOTAL_STEPS}.${C_RST}" >&2
    echo "${C_RED}See the message above and re-run this script after fixing.${C_RST}" >&2
    exit 1
}

trap 'die "Unexpected error on line ${LINENO}."' ERR

banner() {
    echo ""
    echo "${C_BLD}============================================================${C_RST}"
    echo "${C_BLD}  Roche_nxt — Offline Installer${C_RST}"
    echo "${C_BLD}============================================================${C_RST}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_DIR="/opt/roche_nxt"
RUN_USER_OVERRIDE=""
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-root) BUNDLE_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --run-user)    RUN_USER_OVERRIDE="$2"; shift 2 ;;
        -y|--yes)      ASSUME_YES=1; shift ;;
        -h|--help)
            cat <<USAGE
Usage: sudo bash $(basename "$0") [OPTIONS]

Options:
  --bundle-root DIR   Path to the USB bundle root (auto-detected)
  --install-dir DIR   Target install directory (default: /opt/roche_nxt)
  --run-user USER     Owner for .env, log/, and writable dirs (default: \$SUDO_USER)
  -y, --yes           Skip interactive confirmations
  -h, --help          Show this help

USAGE
            exit 0
            ;;
        *) die "Unknown argument: $1" ;;
    esac
done

confirm() {
    local prompt="$1"
    if [[ $ASSUME_YES -eq 1 ]]; then
        return 0
    fi
    local ans
    read -r -p "  ${prompt} [y/N] " ans || true
    [[ "$ans" =~ ^[Yy]$ ]]
}

banner
echo ""
echo "  Bundle root : ${BUNDLE_ROOT}"
echo "  Install dir : ${INSTALL_DIR}"
echo "  Runtime user: $(id -un) (uid=$(id -u) gid=$(id -g))"
echo ""

# ---------------------------------------------------------------------------
# Step 1 — Preflight (OS, privileges, disk, bundle integrity)
# ---------------------------------------------------------------------------
step "Preflight checks"

# 1.1 root/sudo
if [[ $EUID -ne 0 ]]; then
    die "This installer must run as root. Use: sudo bash $(basename "$0")"
fi
ok "Running as root"

# 1.2 OS
if [[ ! -f /etc/os-release ]]; then
    die "/etc/os-release not found — unsupported OS."
fi
# shellcheck disable=SC1091
. /etc/os-release
OS_ID="${ID:-unknown}"
OS_VERSION="${VERSION_ID:-unknown}"
ok "Detected OS: ${PRETTY_NAME:-${OS_ID} ${OS_VERSION}}"

# 1.3 Architecture
ARCH="$(uname -m)"
[[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]] || die "Unsupported arch: $ARCH (expected x86_64)."
ok "Architecture: ${ARCH}"

# 1.4 Bundle layout
for p in images app scripts; do
    [[ -d "${BUNDLE_ROOT}/${p}" ]] || die "Missing directory in bundle: ${BUNDLE_ROOT}/${p}"
done
ok "Bundle structure looks valid"

# 1.5 Disk space check (require ≥ 20 GB free at INSTALL_DIR's parent)
PARENT="$(dirname "$INSTALL_DIR")"
mkdir -p "$PARENT"
AVAIL_KB=$(df -Pk "$PARENT" | awk 'NR==2 {print $4}')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
if [[ $AVAIL_GB -lt 20 ]]; then
    warn "Only ${AVAIL_GB} GB free at ${PARENT}. Recommend ≥ 20 GB for images and runtime."
    confirm "Continue anyway?" || die "Aborted by user."
else
    ok "Disk space: ${AVAIL_GB} GB free at ${PARENT}"
fi

# 1.6 Checksum (optional)
if [[ -f "${BUNDLE_ROOT}/SHA256SUMS" ]]; then
    echo "  Verifying bundle checksums..."
    ( cd "$BUNDLE_ROOT" && sha256sum -c --quiet SHA256SUMS ) \
        && ok "All checksums match" \
        || die "Checksum verification failed. USB may be corrupted."
else
    skip "No SHA256SUMS file — checksum verification skipped"
fi

# ---------------------------------------------------------------------------
# Step 2 — Docker installation (offline)
# ---------------------------------------------------------------------------
step "Docker Engine (offline install)"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    DOCKER_VER="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?')"
    ok "Docker is already installed and running (version ${DOCKER_VER})"
else
    if [[ ! -x "${BUNDLE_ROOT}/scripts/install_docker.sh" ]]; then
        die "Docker not installed and ${BUNDLE_ROOT}/scripts/install_docker.sh is missing."
    fi
    warn "Docker is not installed. Running offline installer..."
    bash "${BUNDLE_ROOT}/scripts/install_docker.sh" --bundle-root "$BUNDLE_ROOT"
    command -v docker >/dev/null 2>&1 || die "Docker still not available after install_docker.sh."
    ok "Docker installed"
fi

# Verify Compose v2 plugin
if docker compose version >/dev/null 2>&1; then
    COMPOSE_VER="$(docker compose version --short 2>/dev/null || echo '?')"
    ok "Docker Compose plugin available (v${COMPOSE_VER})"
else
    die "docker compose (v2 plugin) is not available. Re-run install_docker.sh."
fi

# ---------------------------------------------------------------------------
# Step 3 — Runtime user & docker group
# ---------------------------------------------------------------------------
step "Runtime user and docker group"

# The user that will own .env, log/, and other writable paths.
# Web container runs as UID/GID from .env — files must NOT stay root-owned.
if [[ -n "${RUN_USER_OVERRIDE:-}" ]]; then
    RUN_USER="$RUN_USER_OVERRIDE"
elif [[ -n "${SUDO_USER:-}" ]]; then
    RUN_USER="$SUDO_USER"
else
    die "Cannot determine runtime user. Run with: sudo bash install.sh (from a regular account), or pass --run-user USERNAME"
fi

if ! id "$RUN_USER" >/dev/null 2>&1; then
    die "Runtime user '${RUN_USER}' does not exist on this system."
fi

ok "Runtime user: ${RUN_USER}"

if id -nG "$RUN_USER" | tr ' ' '\n' | grep -qx docker; then
    ok "${RUN_USER} is already in the 'docker' group"
else
    usermod -aG docker "$RUN_USER"
    ok "Added ${RUN_USER} to 'docker' group (takes effect on next login)"
fi

RUN_UID="$(id -u "$RUN_USER")"
RUN_GID="$(id -g "$RUN_USER")"
DOCKER_GID="$(getent group docker | cut -d: -f3 || echo 999)"

# ---------------------------------------------------------------------------
# Step 3b — Upgrade guard: auto-backup critical files if upgrading
# ---------------------------------------------------------------------------
IS_UPGRADE=0
BACKUP_DIR=""

if [[ -f "${INSTALL_DIR}/.env" ]]; then
    IS_UPGRADE=1
    BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    warn "Existing installation detected — creating safety backup before upgrade"
    mkdir -p "$BACKUP_DIR"

    _backed_up=()
    for _f in \
        "${INSTALL_DIR}/.env" \
        "${INSTALL_DIR}/license/license.json" \
        "${INSTALL_DIR}/log/orders_nxt.db"
    do
        if [[ -f "$_f" ]]; then
            cp -p "$_f" "$BACKUP_DIR/"
            _backed_up+=("$(basename "$_f")")
        fi
    done

    if [[ ${#_backed_up[@]} -gt 0 ]]; then
        ok "Backup created: ${BACKUP_DIR}/"
        for _name in "${_backed_up[@]}"; do
            ok "  backed up: ${_name}"
        done
    fi

    echo ""
    warn "Upgrade mode — the following will be REPLACED:"
    warn "  docker-compose.yml, main.nf, nextflow.config, modules/, workflows/, conf/"
    warn "The following will be PRESERVED:"
    warn "  .env, license/, results/, log/, fastq/, work/, bed/, data/"
    echo ""
fi

# ---------------------------------------------------------------------------
# Step 4 — Create install directory and copy app files
# ---------------------------------------------------------------------------
step "Create ${INSTALL_DIR} and copy application files"

mkdir -p "$INSTALL_DIR"

if [[ ! -f "${BUNDLE_ROOT}/app/docker-compose.yml" ]]; then
    die "Missing app/docker-compose.yml in bundle."
fi

cp -f "${BUNDLE_ROOT}/app/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
ok "docker-compose.yml installed"

if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
    if [[ -f "${BUNDLE_ROOT}/app/.env.example" ]]; then
        cp "${BUNDLE_ROOT}/app/.env.example" "${INSTALL_DIR}/.env"
        ok ".env created from template"
    else
        touch "${INSTALL_DIR}/.env"
        skip "No .env.example in bundle; empty .env created"
    fi
else
    ok ".env already exists — preserved"
fi

# Nextflow pipeline files (main.nf, nextflow.config, modules/, workflows/)
if [[ -d "${BUNDLE_ROOT}/app/pipeline" ]]; then
    cp -f "${BUNDLE_ROOT}/app/pipeline/main.nf"         "${INSTALL_DIR}/" 2>/dev/null || true
    cp -f "${BUNDLE_ROOT}/app/pipeline/nextflow.config"  "${INSTALL_DIR}/" 2>/dev/null || true
    if [[ -d "${BUNDLE_ROOT}/app/pipeline/modules" ]]; then
        rm -rf "${INSTALL_DIR}/modules"
        cp -r  "${BUNDLE_ROOT}/app/pipeline/modules"  "${INSTALL_DIR}/"
    fi
    if [[ -d "${BUNDLE_ROOT}/app/pipeline/workflows" ]]; then
        rm -rf "${INSTALL_DIR}/workflows"
        cp -r  "${BUNDLE_ROOT}/app/pipeline/workflows" "${INSTALL_DIR}/"
    fi
    if [[ -d "${BUNDLE_ROOT}/app/pipeline/conf" ]]; then
        rm -rf "${INSTALL_DIR}/conf"
        cp -r  "${BUNDLE_ROOT}/app/pipeline/conf" "${INSTALL_DIR}/"
    fi
    NF_COUNT=$(find "${INSTALL_DIR}" -maxdepth 3 -name "*.nf" 2>/dev/null | wc -l)
    ok "Nextflow pipeline installed (${NF_COUNT} .nf files)"
else
    warn "No pipeline/ directory in bundle — Nextflow files not installed."
    warn "Copy main.nf, nextflow.config, modules/, workflows/ to ${INSTALL_DIR}/ manually."
fi

# ---------------------------------------------------------------------------
# Step 5 — Load Docker images
# ---------------------------------------------------------------------------
step "Load Docker images"

load_image() {
    local tarball="$1"
    local name="$2"
    if [[ ! -f "$tarball" ]]; then
        warn "${name}: ${tarball} not found in bundle — skipping"
        return
    fi
    if docker image inspect "$name" >/dev/null 2>&1; then
        if [[ $IS_UPGRADE -eq 1 ]]; then
            # Upgrade: replace existing image so the new version is actually used
            echo "  Removing old ${name} before loading new version..."
            docker rmi "$name" >/dev/null 2>&1 || true
        else
            ok "${name} already loaded — skipping"
            return
        fi
    fi
    echo "  Loading ${name} from $(basename "$tarball") ($(du -h "$tarball" | awk '{print $1}'))..."
    gunzip -c "$tarball" | docker load
    ok "${name} loaded"
}

load_image "${BUNDLE_ROOT}/images/roche_nxt_web.tar.gz"      "roche_nxt_web:latest"
load_image "${BUNDLE_ROOT}/images/roche_nxt_analysis.tar.gz" "roche_nxt_analysis:latest"

docker image inspect roche_nxt_web:latest >/dev/null \
    || die "roche_nxt_web:latest is not present after image load."

# ---------------------------------------------------------------------------
# Step 6 — Reference data (tarball or pre-extracted directory)
# ---------------------------------------------------------------------------
step "Reference data"

REF_DIR="${DATA_HOST_DIR:-${INSTALL_DIR}/data}"
# Derive DATA_HOST_DIR early so we can use it here (will also be written to .env in step 9)
DATA_HOST_DIR="$REF_DIR"
mkdir -p "$REF_DIR"

# Check if data is already populated (skip extraction if so)
REF_POPULATED=0
if [[ -d "${REF_DIR}/refs" ]] && [[ -n "$(ls -A "${REF_DIR}/refs" 2>/dev/null || true)" ]]; then
    REF_POPULATED=1
fi

if [[ $REF_POPULATED -eq 1 ]]; then
    ok "Reference data already present at ${REF_DIR} — skipping"
else
    DATA_TAR=""
    for cand in \
        "${BUNDLE_ROOT}/data/roche_data.tar.gz" \
        "${BUNDLE_ROOT}/data/roche_data.tar" \
        "${BUNDLE_ROOT}/data/reference.tar.gz"; do
        [[ -f "$cand" ]] && { DATA_TAR="$cand"; break; }
    done
    if [[ -z "$DATA_TAR" ]]; then
        warn "No reference data tarball found in bundle/data/."
        warn "The pipeline will fail at runtime without reference genome files."
        warn ""
        warn "Expected structure under ${REF_DIR}/:"
        warn "  refs/hg38/  — genome FASTA, dbSNP, STAR index, GTF, CTAT lib"
        warn "  snpeff/     — SnpEff databases"
        warn "  bed/hg38/   — panel BED files"
        warn ""
        warn "You can populate this directory manually and re-run the installer."
        confirm "Continue without reference data?" || die "Aborted."
    else
        echo "  Extracting $(basename "$DATA_TAR") to ${REF_DIR}/ (this may take a while)..."
        case "$DATA_TAR" in
            *.tar.gz|*.tgz) tar -xzf "$DATA_TAR" -C "$REF_DIR" --strip-components=1 ;;
            *.tar)          tar -xf  "$DATA_TAR" -C "$REF_DIR" --strip-components=1 ;;
        esac
        ok "Reference data extracted to ${REF_DIR}"
    fi
fi

# Liftover chain (only needed if hg19_view feature is licensed)
LIFTOVER_DIR="${INSTALL_DIR}/liftover"
if [[ -f "${BUNDLE_ROOT}/liftover/hg38ToHg19.over.chain.gz" ]]; then
    mkdir -p "$LIFTOVER_DIR"
    cp -f "${BUNDLE_ROOT}/liftover/hg38ToHg19.over.chain.gz" "$LIFTOVER_DIR/"
    ok "Liftover chain installed at ${LIFTOVER_DIR}"
elif [[ -f "${REF_DIR}/liftover/hg38ToHg19.over.chain.gz" ]]; then
    mkdir -p "$LIFTOVER_DIR"
    cp -f "${REF_DIR}/liftover/hg38ToHg19.over.chain.gz" "$LIFTOVER_DIR/"
    ok "Liftover chain copied from data/ to ${LIFTOVER_DIR}"
else
    skip "No liftover chain in bundle (hg19_view feature will be unavailable)"
fi

# ---------------------------------------------------------------------------
# Step 7 — License file
# ---------------------------------------------------------------------------
step "License"

LIC_DIR="${INSTALL_DIR}/license"
mkdir -p "$LIC_DIR"

if [[ -f "${LIC_DIR}/license.json" ]]; then
    ok "Existing license retained at ${LIC_DIR}/license.json"
else
    SRC_LIC=""
    for cand in "${BUNDLE_ROOT}/license/license.json" "${BUNDLE_ROOT}"/license/*.json; do
        [[ -f "$cand" ]] && { SRC_LIC="$cand"; break; }
    done
    if [[ -z "$SRC_LIC" ]]; then
        die "No license file found in ${BUNDLE_ROOT}/license/. Cannot continue."
    fi
    cp -f "$SRC_LIC" "${LIC_DIR}/license.json"
    ok "License installed from $(basename "$SRC_LIC")"
fi
chmod 0444 "${LIC_DIR}/license.json"
ok "License set to read-only (0444)"

# ---------------------------------------------------------------------------
# Step 8 — Runtime directories
# ---------------------------------------------------------------------------
step "Create runtime directories"

for d in results work log fastq bed data liftover; do
    target="${INSTALL_DIR}/${d}"
    if [[ -d "$target" ]]; then
        ok "${d}/ already exists"
    else
        mkdir -p "$target"
        ok "${d}/ created"
    fi
done

# Ownership is applied after .env is written (step 9) so UID/GID match the runtime user.

# ---------------------------------------------------------------------------
# Step 9 — Configure .env
# ---------------------------------------------------------------------------
step "Configure .env"

ENV_FILE="${INSTALL_DIR}/.env"

upsert() {
    local key="$1" val="$2"
    if grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >> "$ENV_FILE"
    fi
}

upsert HOST_DIR           "$INSTALL_DIR"
upsert UID                "$RUN_UID"
upsert GID                "$RUN_GID"
upsert DOCKER_GID         "$DOCKER_GID"
upsert RESULTS_HOST_DIR   "${INSTALL_DIR}/results"
upsert WORK_HOST_DIR      "${INSTALL_DIR}/work"
upsert LOG_HOST_DIR       "${INSTALL_DIR}/log"
upsert FASTQ_HOST_DIR     "${INSTALL_DIR}/fastq"
upsert BED_HOST_DIR       "${INSTALL_DIR}/bed"
upsert LIFTOVER_HOST_DIR  "${INSTALL_DIR}/liftover"
upsert LICENSE_HOST_DIR   "${INSTALL_DIR}/license"
upsert WEB_PORT           "${WEB_PORT:-8080}"
upsert TZ                 "${TZ:-Asia/Seoul}"

# DATA_HOST_DIR: reference data root (genome, STAR index, CTAT lib, etc.)
# Defaults to HOST_DIR/data; set it explicitly if refs are on a separate disk.
DATA_DIR="${INSTALL_DIR}/data"
upsert DATA_HOST_DIR      "$DATA_DIR"

# Hard-remove DEV_MODE / ENABLE_* if present — prod must not have these
sed -i -E '/^(DEV_MODE|ENABLE_LONGITUDINAL|ENABLE_IGV|ENABLE_HG19_VIEW)=/d' "$ENV_FILE"

ok ".env updated (paths, UID/GID, runtime dirs)"
ok "DEV_MODE and ENABLE_* entries removed (production hygiene)"

# Web container runs as UID/GID from .env. Install steps above run as root,
# so without chown the UI cannot write .env or the SQLite DB under log/.
fix_runtime_ownership() {
    chown "${RUN_UID}:${RUN_GID}" "${ENV_FILE}"
    chown "${RUN_UID}:${RUN_GID}" "${INSTALL_DIR}/docker-compose.yml"
    chown -R "${RUN_UID}:${RUN_GID}" \
        "${INSTALL_DIR}/results" \
        "${INSTALL_DIR}/work" \
        "${INSTALL_DIR}/log" \
        "${INSTALL_DIR}/fastq" \
        "${INSTALL_DIR}/bed"
    for f in main.nf nextflow.config; do
        [[ -f "${INSTALL_DIR}/${f}" ]] && chown "${RUN_UID}:${RUN_GID}" "${INSTALL_DIR}/${f}"
    done
    for d in modules workflows conf; do
        [[ -d "${INSTALL_DIR}/${d}" ]] && chown -R "${RUN_UID}:${RUN_GID}" "${INSTALL_DIR}/${d}"
    done
}
fix_runtime_ownership
ok "Ownership: .env, docker-compose.yml, log/, pipeline/ → ${RUN_USER} (${RUN_UID}:${RUN_GID})"

# ---------------------------------------------------------------------------
# Step 10 — Launch the stack
# ---------------------------------------------------------------------------
step "Start the Roche_nxt stack"

cd "$INSTALL_DIR"
docker compose pull 2>/dev/null || true   # will no-op in air-gap; ignore
docker compose up -d
ok "Stack started"

echo ""
echo "  Waiting up to 30s for the web container to become healthy..."
for i in {1..30}; do
    if docker compose logs --tail=50 roche-nxt-web 2>&1 | grep -qE "License OK|Running on http"; then
        ok "Web service is up"
        break
    fi
    if docker compose ps | grep -q "Exited"; then
        echo ""
        docker compose logs --tail=40 roche-nxt-web || true
        die "Container exited during startup (likely license/config issue)."
    fi
    sleep 1
    [[ $i -eq 30 ]] && warn "Still starting — check logs manually: docker compose logs -f roche-nxt-web"
done

# ---------------------------------------------------------------------------
# Step 11 — Final health check & summary
# ---------------------------------------------------------------------------
step "Verify"

WEB_PORT_VAL="$(grep -E '^WEB_PORT=' "$ENV_FILE" | cut -d= -f2 || echo 8080)"

docker compose ps
echo ""

if curl -fs -o /dev/null -w "%{http_code}" "http://127.0.0.1:${WEB_PORT_VAL}/" 2>/dev/null | grep -qE "^(200|302)$"; then
    ok "HTTP probe passed on port ${WEB_PORT_VAL}"
else
    warn "HTTP probe did not succeed on port ${WEB_PORT_VAL} (may still be starting)."
fi

FEATURES_JSON="$(curl -fs "http://127.0.0.1:${WEB_PORT_VAL}/api/features" 2>/dev/null || echo '')"
if [[ -n "$FEATURES_JSON" ]]; then
    echo ""
    echo "  Licensed features:"
    echo "$FEATURES_JSON" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
lic = d.get("license", {})
print("    customer : {}".format(lic.get("customer", "?")))
print("    expires  : {}".format(lic.get("expires") or "never"))
print("    dev_mode : {}".format(lic.get("dev_mode", False)))
for k in ("longitudinal", "igv", "hg19_view"):
    print("    {:12s}: {}".format(k, d.get(k, False)))
' 2>/dev/null || true
fi

echo ""
echo "${C_GRN}${C_BLD}============================================================${C_RST}"
echo "${C_GRN}${C_BLD}  Installation complete.${C_RST}"
echo "${C_GRN}${C_BLD}============================================================${C_RST}"
cat <<EOF

  Web UI     : http://<this-server-ip>:${WEB_PORT_VAL}/
  Install dir: ${INSTALL_DIR}
  Config     : ${INSTALL_DIR}/.env
  Logs       : docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f

  Daily operations:
    cd ${INSTALL_DIR}
    docker compose ps
    docker compose restart roche-nxt-web
    docker compose down
    docker compose up -d

  Place FASTQ inputs under: ${INSTALL_DIR}/fastq/
  Place BED targets under : ${INSTALL_DIR}/bed/
  Results will appear in  : ${INSTALL_DIR}/results/

EOF

if [[ $IS_UPGRADE -eq 1 && -n "$BACKUP_DIR" ]]; then
    echo "${C_YEL}  Upgrade backup (safe to delete once verified):${C_RST}"
    echo "    ${BACKUP_DIR}/"
    for _f in "$BACKUP_DIR"/*; do
        [[ -f "$_f" ]] && echo "      $(basename "$_f")  ($(du -sh "$_f" 2>/dev/null | cut -f1))"
    done
    echo ""
    echo "  To roll back, restore from backup:"
    echo "    cp ${BACKUP_DIR}/.env              ${INSTALL_DIR}/"
    echo "    cp ${BACKUP_DIR}/license.json      ${INSTALL_DIR}/license/"
    echo "    cp ${BACKUP_DIR}/orders_nxt.db     ${INSTALL_DIR}/log/"
    echo ""
fi
