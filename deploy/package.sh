#!/bin/bash
#
# Roche Panel Analysis - 배포 패키지 생성 스크립트
#
# 온라인 서버에서 실행하여 폐쇄망 배포용 패키지를 생성합니다.
#
# 생성되는 파일:
#   1. roche_panel_analysis_code.tar.gz     - 파이프라인 코드 (~5 MB)
#   2. roche_panel_analysis_images.tar.gz   - Docker 이미지 (~3 GB)
#   3. roche_data.tar.gz                    - 레퍼런스 데이터 (~140 GB, 선택)
#
# 사용법:
#   bash deploy/package.sh                  # 코드 + 이미지
#   bash deploy/package.sh --with-data      # 코드 + 이미지 + 레퍼런스 데이터
#   bash deploy/package.sh --code-only      # 코드만 (업데이트 시)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/deploy/packages"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

WITH_DATA=false
CODE_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --with-data) WITH_DATA=true ;;
        --code-only) CODE_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --with-data    Include reference data (~140GB)"
            echo "  --code-only    Package code only (for updates)"
            echo "  --help         Show this help"
            exit 0
            ;;
    esac
done

echo ""
echo "============================================"
echo "  Roche Panel Analysis - Package Builder"
echo "============================================"
echo ""

mkdir -p "$OUTPUT_DIR"

# ── 1. Code package ───────────────────────────────────────
log_info "[1/3] Creating code package..."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CODE_PKG="roche_panel_analysis_code.tar.gz"

cd "$(dirname "$PROJECT_DIR")"

tar czf "${PROJECT_DIR}/deploy/packages/${CODE_PKG}" \
    --exclude="${PROJECT_NAME}/data" \
    --exclude="${PROJECT_NAME}/work" \
    --exclude="${PROJECT_NAME}/results" \
    --exclude="${PROJECT_NAME}/log" \
    --exclude="${PROJECT_NAME}/fastq" \
    --exclude="${PROJECT_NAME}/.nextflow" \
    --exclude="${PROJECT_NAME}/.nextflow.log*" \
    --exclude="${PROJECT_NAME}/.git" \
    --exclude="${PROJECT_NAME}/.env" \
    --exclude="${PROJECT_NAME}/deploy/packages" \
    --exclude="${PROJECT_NAME}/deploy/images" \
    --exclude="${PROJECT_NAME}/__pycache__" \
    --exclude="*.pyc" \
    "${PROJECT_NAME}/"

CODE_SIZE=$(ls -lh "${OUTPUT_DIR}/${CODE_PKG}" | awk '{print $5}')
log_ok "Code package: ${OUTPUT_DIR}/${CODE_PKG} (${CODE_SIZE})"

if [ "$CODE_ONLY" = true ]; then
    echo ""
    log_ok "Code-only packaging complete!"
    echo ""
    echo "Files:"
    ls -lh "${OUTPUT_DIR}/${CODE_PKG}"
    echo ""
    echo "To deploy on target server:"
    echo "  1. Copy ${CODE_PKG} to target"
    echo "  2. tar xzf ${CODE_PKG}"
    echo "  3. make restart"
    exit 0
fi

# ── 2. Docker images ─────────────────────────────────────
log_info "[2/3] Saving Docker images..."

IMAGES_PKG="roche_panel_analysis_images.tar.gz"
ANALYSIS_IMAGE="roche_nxt_analysis:latest"
WEB_IMAGE="roche_nxt_web:latest"

MISSING_IMAGES=false
if ! docker image inspect ${ANALYSIS_IMAGE} &>/dev/null; then
    log_error "Analysis image not found. Run 'make build-analysis' first."
    MISSING_IMAGES=true
fi
if ! docker image inspect ${WEB_IMAGE} &>/dev/null; then
    log_error "Web image not found. Run 'make build-web' first."
    MISSING_IMAGES=true
fi

if [ "$MISSING_IMAGES" = true ]; then
    log_error "Missing Docker images. Please build them first:"
    echo "  make build"
    exit 1
fi

log_info "  Saving ${ANALYSIS_IMAGE} and ${WEB_IMAGE}..."
docker save ${ANALYSIS_IMAGE} ${WEB_IMAGE} | gzip > "${OUTPUT_DIR}/${IMAGES_PKG}"

IMAGES_SIZE=$(ls -lh "${OUTPUT_DIR}/${IMAGES_PKG}" | awk '{print $5}')
log_ok "Images package: ${OUTPUT_DIR}/${IMAGES_PKG} (${IMAGES_SIZE})"

# ── 3. Reference data (optional) ─────────────────────────
if [ "$WITH_DATA" = true ]; then
    log_info "[3/3] Packaging reference data..."

    DATA_PKG="roche_data.tar.gz"

    DATA_TARGET=""
    if [ -L "${PROJECT_DIR}/data" ]; then
        DATA_TARGET=$(readlink -f "${PROJECT_DIR}/data")
    elif [ -d "${PROJECT_DIR}/data" ]; then
        DATA_TARGET="${PROJECT_DIR}/data"
    fi

    if [ -z "$DATA_TARGET" ] || [ ! -d "$DATA_TARGET" ]; then
        log_error "Reference data directory not found!"
        log_error "Expected: ${PROJECT_DIR}/data -> /path/to/roche_data"
    else
        DATA_PARENT=$(dirname "$DATA_TARGET")
        DATA_DIRNAME=$(basename "$DATA_TARGET")

        log_info "  Source: ${DATA_TARGET}"
        log_warn "  This may take a long time for large reference datasets..."

        cd "$DATA_PARENT"
        tar czf "${OUTPUT_DIR}/${DATA_PKG}" "${DATA_DIRNAME}/"

        DATA_SIZE=$(ls -lh "${OUTPUT_DIR}/${DATA_PKG}" | awk '{print $5}')
        log_ok "Data package: ${OUTPUT_DIR}/${DATA_PKG} (${DATA_SIZE})"
    fi
else
    log_info "[3/3] Skipping reference data (use --with-data to include)"
fi

# ── Summary ──────────────────────────────────────────────
echo ""
echo "============================================"
log_ok "Packaging complete!"
echo "============================================"
echo ""
echo "Generated files:"
ls -lh "${OUTPUT_DIR}/"*.tar.gz 2>/dev/null
echo ""
echo "Deployment steps on target server:"
echo "  1. Copy all .tar.gz files to target server"
echo "  2. tar xzf ${CODE_PKG}"
if [ "$WITH_DATA" = true ]; then
echo "  3. tar xzf roche_data.tar.gz"
echo "  4. cd ${PROJECT_NAME} && ln -s ../roche_data data"
echo "  5. bash deploy/install.sh"
else
echo "  3. cd ${PROJECT_NAME} && ln -s /path/to/roche_data data"
echo "  4. bash deploy/install.sh"
fi
echo ""
