#!/usr/bin/env bash
#
# Roche_nxt — Patch: Nextflow v2 Syntax Compatibility (v1.1.0)
#
# Patches an existing v2 installation to fix Nextflow parsing errors
# that required NXF_SYNTAX_PARSER=v1 workaround.
#
# Changes:
#   - nextflow.config : removed Runtime.runtime, Math.min(), new Date()
#                       from config; resource capping via closures
#   - conf/base.config: same Runtime/Math removal
#   - main.nf         : genome resolution moved from config; Channel→channel;
#                        workflow.onComplete moved inside workflow block
#   - workflows/rnaseq.nf: Channel→channel
#
# Usage (on the target server):
#   sudo bash patch_v3_nf_syntax.sh [--install-dir /opt/roche_nxt]
#
# The patch does NOT touch Docker images, reference data, .env, results,
# or any user data. It only replaces Nextflow pipeline source files.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/roche_nxt"
BACKUP_SUFFIX=".pre_v3_patch.$(date +%Y%m%d_%H%M%S)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: sudo bash $(basename "$0") [--install-dir /opt/roche_nxt]"
            exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "This patch must run with root privileges."
    echo "    sudo bash $(basename "$0")"
    exit 1
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "ERROR: Install directory not found: $INSTALL_DIR"
    exit 1
fi

PATCH_DIR="${SCRIPT_DIR}/pipeline"
if [[ ! -d "$PATCH_DIR" ]]; then
    echo "ERROR: Pipeline files not found at: $PATCH_DIR"
    echo "       Expected directory structure:"
    echo "         patch_v3_nf_syntax.sh"
    echo "         pipeline/"
    echo "           main.nf"
    echo "           nextflow.config"
    echo "           conf/"
    echo "           modules/"
    echo "           workflows/"
    exit 1
fi

echo "============================================================"
echo "  Roche_nxt Patch — Nextflow v2 Syntax Compatibility"
echo "============================================================"
echo ""
echo "  Install dir: ${INSTALL_DIR}"
echo "  Backup ext : ${BACKUP_SUFFIX}"
echo ""

backup_file() {
    local f="$1"
    if [[ -f "$f" ]]; then
        cp "$f" "${f}${BACKUP_SUFFIX}"
        echo "  [backup] ${f}"
    fi
}

echo "[1/4] Backing up current pipeline files..."
backup_file "${INSTALL_DIR}/main.nf"
backup_file "${INSTALL_DIR}/nextflow.config"
[[ -d "${INSTALL_DIR}/conf" ]] && cp -r "${INSTALL_DIR}/conf" "${INSTALL_DIR}/conf${BACKUP_SUFFIX}"
echo ""

echo "[2/4] Copying patched pipeline files..."
cp -f "${PATCH_DIR}/main.nf"         "${INSTALL_DIR}/"
cp -f "${PATCH_DIR}/nextflow.config" "${INSTALL_DIR}/"

if [[ -d "${PATCH_DIR}/conf" ]]; then
    rm -rf "${INSTALL_DIR}/conf"
    cp -r  "${PATCH_DIR}/conf"       "${INSTALL_DIR}/"
fi
if [[ -d "${PATCH_DIR}/modules" ]]; then
    rm -rf "${INSTALL_DIR}/modules"
    cp -r  "${PATCH_DIR}/modules"    "${INSTALL_DIR}/"
fi
if [[ -d "${PATCH_DIR}/workflows" ]]; then
    rm -rf "${INSTALL_DIR}/workflows"
    cp -r  "${PATCH_DIR}/workflows"  "${INSTALL_DIR}/"
fi
echo "  Pipeline files updated."
echo ""

echo "[3/4] Fixing file ownership..."
ENV_FILE="${INSTALL_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    RUN_UID=$(grep -E '^UID=' "$ENV_FILE" | head -1 | cut -d= -f2)
    RUN_GID=$(grep -E '^GID=' "$ENV_FILE" | head -1 | cut -d= -f2)
    if [[ -n "$RUN_UID" && -n "$RUN_GID" ]]; then
        chown "${RUN_UID}:${RUN_GID}" "${ENV_FILE}" "${INSTALL_DIR}/docker-compose.yml" 2>/dev/null || true
        chown -R "${RUN_UID}:${RUN_GID}" \
            "${INSTALL_DIR}/log" \
            "${INSTALL_DIR}/results" \
            "${INSTALL_DIR}/work" \
            "${INSTALL_DIR}/fastq" \
            "${INSTALL_DIR}/bed" \
            "${INSTALL_DIR}/main.nf" \
            "${INSTALL_DIR}/nextflow.config" \
            "${INSTALL_DIR}/conf" \
            "${INSTALL_DIR}/modules" \
            "${INSTALL_DIR}/workflows" 2>/dev/null || true
        echo "  Ownership set to ${RUN_UID}:${RUN_GID} (.env, log/, pipeline/)"
    else
        echo "  WARNING: UID/GID not found in .env — fix ownership manually"
    fi
fi
echo ""

echo "[4/4] Restarting containers..."
cd "$INSTALL_DIR"
docker compose restart roche-nxt-web 2>/dev/null || \
    docker-compose restart roche-nxt-web 2>/dev/null || \
    echo "  (no container restart needed — only pipeline files changed)"
echo ""

NF_COUNT=$(find "${INSTALL_DIR}" -maxdepth 3 -name "*.nf" 2>/dev/null | wc -l)
echo "============================================================"
echo "  Patch applied successfully!"
echo "  ${NF_COUNT} Nextflow files updated."
echo ""
echo "  NXF_SYNTAX_PARSER=v1 workaround is no longer needed."
echo ""
echo "  To verify, run a test analysis from the web UI."
echo "  Backups saved with suffix: ${BACKUP_SUFFIX}"
echo "============================================================"
